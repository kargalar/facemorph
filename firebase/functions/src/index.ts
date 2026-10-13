import {getAuth} from "firebase-admin/auth";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldPath, FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
import {createHmac} from "node:crypto";
import {google} from "googleapis";

if (getApps().length === 0) initializeApp();

const premiumProductId = "oneframe_premium_monthly";
const androidPackageName = "app.facemorph";
const trialDurationMs = 14 * 24 * 60 * 60 * 1000;
const maxPhotoBytes = 10 * 1024 * 1024;
const bunnyTokenTtlSeconds = 365 * 24 * 60 * 60;

class HttpRequestError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}

interface BunnyConfig {
  accessKey: string;
  tokenAuthKey: string;
  storageHostname: string;
  storageZone: string;
  cdnBaseUrl: string;
}

export const verifyPremiumPurchase = onCall(
  {region: "europe-west1"},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    const productId = String(request.data?.productId ?? "");
    const source = String(request.data?.source ?? "");
    const verificationData = String(request.data?.verificationData ?? "");
    if (productId !== premiumProductId || verificationData.length === 0) {
      throw new HttpsError("invalid-argument", "Invalid purchase payload.");
    }

    if (!source.toLowerCase().includes("google")) {
      throw new HttpsError(
        "failed-precondition",
        "Google Play verification is the only configured store.",
      );
    }
    const premiumUntil = await verifyGooglePlay(verificationData);
    if (premiumUntil <= Date.now()) {
      throw new HttpsError("failed-precondition", "Subscription is not active.");
    }

    await getFirestore().collection("users").doc(request.auth.uid).update({
      premiumUntil: Timestamp.fromMillis(premiumUntil),
      premiumSource: source,
      premiumVerifiedAt: FieldValue.serverTimestamp(),
    });
    return {premiumUntil};
  },
);

export const deleteAccount = onCall(
  {
    region: "europe-west1",
    preserveExternalChanges: true,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign-in required.");

    const firestore = getFirestore();
    const userRef = firestore.collection("users").doc(uid);
    const following = await userRef.collection("following").get();
    const incomingFollowers = await firestore
      .collectionGroup("followers")
      .where(FieldPath.documentId(), "==", uid)
      .get();
    const ownedPhotos = await firestore
      .collection("photos")
      .where("ownerId", "==", uid)
      .get();
    const bulkWriter = firestore.bulkWriter();

    for (const followed of following.docs) {
      bulkWriter.delete(
        firestore.collection("users").doc(followed.id).collection("followers").doc(uid),
      );
    }
    for (const follower of incomingFollowers.docs) bulkWriter.delete(follower.ref);
    for (const photo of ownedPhotos.docs) bulkWriter.delete(photo.ref);

    await firestore.recursiveDelete(userRef, bulkWriter);
    await bulkWriter.close();
    await deleteBunnyObject(getBunnyConfig(), `users/${uid}/photos`);

    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      const code = (error as {code?: string}).code;
      if (code !== "auth/user-not-found") throw error;
    }
    return {deleted: true};
  },
);

export const deleteAllPhotos = onCall(
  {
    region: "europe-west1",
    preserveExternalChanges: true,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign-in required.");

    const firestore = getFirestore();
    const ownedPhotos = await firestore
      .collection("photos")
      .where("ownerId", "==", uid)
      .get();
    const storagePaths = ownedPhotos.docs
      .map((photo) => photo.data().storagePath)
      .filter((path): path is string =>
        typeof path === "string" && isOwnedPhotoPath(uid, path),
      );

    if (storagePaths.length > 0) {
      const config = getBunnyConfig();
      await Promise.all(
        storagePaths.map((storagePath) =>
          deleteBunnyObject(config, storagePath),
        ),
      );
    }

    const bulkWriter = firestore.bulkWriter();
    for (const photo of ownedPhotos.docs) bulkWriter.delete(photo.ref);
    await bulkWriter.close();
    return {deleted: ownedPhotos.size};
  },
);

export const uploadPhoto = onRequest(
  {
    region: "europe-west1",
    preserveExternalChanges: true,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).json({error: "Method not allowed."});
      return;
    }

    try {
      const uid = await authenticatedUid(request);
      const contentType = (request.get("content-type") ?? "")
        .split(";", 1)[0]
        .toLowerCase();
      const dayKey = request.get("x-photo-day-key") ?? "";
      const capturedAt = Date.parse(request.get("x-captured-at") ?? "");
      const body = request.rawBody;
      if (contentType !== "image/jpeg" || !body || body.length === 0) {
        throw new HttpRequestError(400, "A JPEG photo is required.");
      }
      if (body.length > maxPhotoBytes) {
        throw new HttpRequestError(413, "Photo is too large.");
      }
      if (!isValidDayKey(dayKey) || !Number.isFinite(capturedAt)) {
        throw new HttpRequestError(400, "Invalid photo date.");
      }
      if (capturedAt > Date.now() + 60_000) {
        throw new HttpRequestError(400, "Photo date cannot be in the future.");
      }

      const storagePath = `users/${uid}/photos/${dayKey}.jpg`;
      const config = getBunnyConfig();
      await uploadToBunny(config, storagePath, body);
      response.status(200).json({
        url: bunnyCdnUrl(config, storagePath),
        storagePath,
      });
    } catch (error) {
      respondToHttpError(response, error, "Photo upload failed.");
    }
  },
);

export const deletePhoto = onRequest(
  {
    region: "europe-west1",
    preserveExternalChanges: true,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).json({error: "Method not allowed."});
      return;
    }

    try {
      const uid = await authenticatedUid(request);
      const photoId = request.body?.photoId;
      if (typeof photoId !== "string" || photoId.length === 0) {
        throw new HttpRequestError(400, "Photo id is required.");
      }

      const photo = getFirestore().collection("photos").doc(photoId);
      const snapshot = await photo.get();
      if (!snapshot.exists) {
        response.status(404).json({error: "Photo not found."});
        return;
      }
      const data = snapshot.data()!;
      if (data.ownerId !== uid) {
        throw new HttpRequestError(403, "Only your own photos can be deleted.");
      }

      const storagePath = data.storagePath;
      if (typeof storagePath === "string" && isOwnedPhotoPath(uid, storagePath)) {
        await deleteBunnyObject(getBunnyConfig(), storagePath);
      }
      await photo.delete();
      response.status(200).json({deleted: true});
    } catch (error) {
      respondToHttpError(response, error, "Photo deletion failed.");
    }
  },
);

async function authenticatedUid(request: {
  get(name: string): string | undefined;
}): Promise<string> {
  const authorization = request.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    throw new HttpRequestError(401, "Sign-in required.");
  }
  try {
    return (await getAuth().verifyIdToken(authorization.substring(7))).uid;
  } catch {
    throw new HttpRequestError(401, "Invalid authentication token.");
  }
}

function getBunnyConfig(): BunnyConfig {
  const accessKey = (process.env.BUNNY_STORAGE_ACCESS_KEY ?? "").trim();
  const tokenAuthKey = (process.env.BUNNY_TOKEN_AUTH_KEY ?? "").trim();
  const storageZone = process.env.BUNNY_STORAGE_ZONE?.trim() ?? "";
  const storageHostname =
    process.env.BUNNY_STORAGE_HOSTNAME?.trim() || "storage.bunnycdn.com";
  const cdnBaseUrl = process.env.BUNNY_CDN_BASE_URL?.trim().replace(/\/+$/, "") ?? "";
  if (!accessKey || !tokenAuthKey || !storageZone || !cdnBaseUrl) {
    throw new Error("Bunny Storage configuration is incomplete.");
  }
  return {accessKey, tokenAuthKey, storageHostname, storageZone, cdnBaseUrl};
}

async function uploadToBunny(
  config: BunnyConfig,
  storagePath: string,
  body: Buffer,
): Promise<void> {
  const response = await fetch(bunnyStorageUrl(config, storagePath), {
    method: "PUT",
    headers: {
      AccessKey: config.accessKey,
      "Cache-Control": "public,max-age=31536000",
      "Content-Type": "image/jpeg",
    },
    body: new Uint8Array(body),
  });
  if (!response.ok) {
    throw new Error(`Bunny upload failed with status ${response.status}.`);
  }
}

async function deleteBunnyObject(
  config: BunnyConfig,
  storagePath: string,
): Promise<void> {
  const response = await fetch(bunnyStorageUrl(config, storagePath), {
    method: "DELETE",
    headers: {AccessKey: config.accessKey},
  });
  if (!response.ok && response.status !== 404) {
    throw new Error(`Bunny deletion failed with status ${response.status}.`);
  }
}

function bunnyStorageUrl(config: BunnyConfig, storagePath: string): string {
  const path = storagePath.split("/").map(encodeURIComponent).join("/");
  return `https://${config.storageHostname}/${encodeURIComponent(config.storageZone)}/${path}`;
}

function bunnyCdnUrl(config: BunnyConfig, storagePath: string): string {
  const path = storagePath.split("/").map(encodeURIComponent).join("/");
  const expires = Math.floor(Date.now() / 1000) + bunnyTokenTtlSeconds;
  const token = createHmac("sha256", config.tokenAuthKey)
    .update(`/${path}${expires}`)
    .digest("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  return `${config.cdnBaseUrl}/${path}?token=HS256-${token}&expires=${expires}`;
}

function isValidDayKey(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

function isOwnedPhotoPath(uid: string, storagePath: string): boolean {
  const prefix = `users/${uid}/photos/`;
  return storagePath.startsWith(prefix) &&
    /^\d{4}-\d{2}-\d{2}\.jpg$/.test(storagePath.substring(prefix.length));
}

function respondToHttpError(
  response: {status(code: number): {json(body: unknown): void}},
  error: unknown,
  fallbackMessage: string,
): void {
  if (error instanceof HttpRequestError) {
    response.status(error.status).json({error: error.message});
    return;
  }
  console.error(error);
  response.status(500).json({error: fallbackMessage});
}

async function verifyGooglePlay(purchaseToken: string): Promise<number> {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const publisher = google.androidpublisher({version: "v3", auth});
  const response = await publisher.purchases.subscriptionsv2.get({
    packageName: androidPackageName,
    token: purchaseToken,
  });
  const validStates = new Set([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  ]);
  if (!validStates.has(response.data.subscriptionState ?? "")) {
    throw new HttpsError("failed-precondition", "Google Play subscription is inactive.");
  }
  const expiries = (response.data.lineItems ?? [])
    .filter((item) => item.productId === premiumProductId)
    .map((item) => Date.parse(item.expiryTime ?? ""))
    .filter(Number.isFinite);
  if (expiries.length === 0) throw new HttpsError("data-loss", "Missing subscription expiry.");
  return Math.max(...expiries);
}

export const enforceCaptureQuota = onDocumentCreated(
  {
    document: "photos/{photoId}",
    region: "europe-west1",
    preserveExternalChanges: true,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const photo = snapshot.data();
    const ownerId = String(photo.ownerId ?? "");
    const userSnapshot = await getFirestore().collection("users").doc(ownerId).get();
    if (!userSnapshot.exists) return removePhoto(snapshot.ref.path, photo.storagePath);

    const user = userSnapshot.data()!;
    const capturedAt = (photo.capturedAt as Timestamp).toDate();
    const trialStart = (user.trialStartedAt as Timestamp).toMillis();
    const premiumUntil = (user.premiumUntil as Timestamp | undefined)?.toMillis() ?? 0;
    const isPremium = Math.max(trialStart + trialDurationMs, premiumUntil) > capturedAt.getTime();
    const start = isPremium ? startOfUtcDay(capturedAt) : startOfUtcWeek(capturedAt);
    const existing = await getFirestore()
      .collection("photos")
      .where("ownerId", "==", ownerId)
      .where("capturedAt", ">=", Timestamp.fromDate(start))
      .where("capturedAt", "<", Timestamp.fromDate(isPremium ? addDays(start, 1) : addDays(start, 7)))
      .get();
    if (existing.size > 1) await removePhoto(snapshot.ref.path, photo.storagePath);
  },
);

async function removePhoto(documentPath: string, storagePath: unknown): Promise<void> {
  await getFirestore().doc(documentPath).delete();
  if (typeof storagePath === "string") {
    await deleteBunnyObject(getBunnyConfig(), storagePath);
  }
}

function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function startOfUtcWeek(date: Date): Date {
  const start = startOfUtcDay(date);
  const day = start.getUTCDay() || 7;
  start.setUTCDate(start.getUTCDate() - day + 1);
  return start;
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}
