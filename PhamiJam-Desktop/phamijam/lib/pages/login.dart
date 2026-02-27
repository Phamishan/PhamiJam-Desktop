import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:phamijam/services/google_auth_service.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _userId;
  bool _isLoading = false;

  Future<UserCredential?> _firebaseSignInFromGoogleCredentials(
    GoogleSignInCredentials credentials,
  ) async {
    final hasIdToken = (credentials.idToken ?? '').isNotEmpty;
    final hasAccessToken = credentials.accessToken.isNotEmpty;

    if (!hasIdToken && !hasAccessToken) {
      return null;
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: hasAccessToken ? credentials.accessToken : null,
      idToken: hasIdToken ? credentials.idToken : null,
    );

    return _auth.signInWithCredential(credential);
  }

  Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Trigger the authentication flow
      final credentials = await GoogleAuthService.signIn();

      if (credentials == null) {
        // User canceled the sign-in
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        return;
      }

      var userCredential = await _firebaseSignInFromGoogleCredentials(
        credentials,
      );

      if (userCredential == null) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'Google sign-in did not return usable tokens.',
        );
      }

      if (!mounted) return;
      setState(() {
        _userId = userCredential.user?.email;
        _isLoading = false;
      });
    } on FirebaseAuthException catch (error) {
      if (error.code == 'invalid-credential') {
        try {
          final refreshedCredentials = await GoogleAuthService.signInFresh();
          if (refreshedCredentials != null) {
            final retriedUserCredential =
                await _firebaseSignInFromGoogleCredentials(
                  refreshedCredentials,
                );

            if (retriedUserCredential != null && mounted) {
              setState(() {
                _userId = retriedUserCredential.user?.email;
                _isLoading = false;
              });
              return;
            }
          }
        } catch (_) {}
      }

      debugPrint('Error signing in with Google: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == 'invalid-credential'
                  ? 'Google sign-in token expired. Please try again.'
                  : 'Failed to sign in: ${error.message ?? error.code}',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Error signing in with Google: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to sign in: $error')));
      }
    }
  }

  Future<void> _signOut() async {
    await GoogleAuthService.signOut();
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _userId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _userId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFdba43a),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Container(
                      width: 350.0,
                      padding: EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        color: const Color(0xFFb5832e),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(height: 8),
                          Image.asset(
                            "assets/images/p-trans.png",
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                          SizedBox(height: 18),
                          Text(
                            "Welcome to PhamiJam",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            _userId != null
                                ? "Logged in as $_userId"
                                : "Please log in with your Google account to continue.",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 24),
                          if (_isLoading)
                            CircularProgressIndicator(color: Colors.white)
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: () async {
                                    if (isSignedIn) {
                                      await _signOut();
                                    } else {
                                      await _signInWithGoogle();
                                    }
                                  },
                                  icon: ClipOval(
                                    child: Image.asset(
                                      "assets/images/google_icon.jpg",
                                      width: 36,
                                      height: 36,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  iconSize: 40,
                                  splashRadius: 24,
                                  tooltip: isSignedIn
                                      ? 'Sign Out'
                                      : 'Sign In with Google',
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
