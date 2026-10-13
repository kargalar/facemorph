import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  bool _googleInitialized = false;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  User? get currentUser => _firebaseAuth.currentUser;

  bool get currentUserUsesPassword =>
      currentUser?.providerData.any(
        (provider) => provider.providerId == EmailAuthProvider.PROVIDER_ID,
      ) ??
      false;

  Future<UserCredential> signInWithGoogle() async {
    await _initializeGoogle();
    final googleUser = await _googleSignIn.authenticate();
    final credential = GoogleAuthProvider.credential(
      idToken: googleUser.authentication.idToken,
    );
    return _firebaseAuth.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _firebaseAuth.signInWithEmailAndPassword(
    email: email.trim(),
    password: password,
  );

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) => _firebaseAuth.createUserWithEmailAndPassword(
    email: email.trim(),
    password: password,
  );

  Future<void> sendPasswordResetEmail(String email) =>
      _firebaseAuth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    if (_googleInitialized) await _googleSignIn.signOut();
  }

  Future<void> reauthenticate({String? password}) async {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Authentication is required.',
      );
    }

    if (currentUserUsesPassword) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw FirebaseAuthException(
          code: 'password-required',
          message: 'The account password is required.',
        );
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return;
    }

    await _initializeGoogle();
    final googleUser = await _googleSignIn.authenticate();
    await user.reauthenticateWithCredential(
      GoogleAuthProvider.credential(idToken: googleUser.authentication.idToken),
    );
  }

  Future<void> _initializeGoogle() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
    _googleInitialized = true;
  }
}
