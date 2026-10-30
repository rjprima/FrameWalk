import 'package:flutter/material.dart';

import 'login_page.dart';
import 'create_account_page.dart';

// The landing page where users can log in or create account
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Text(
                  'FrameWalk',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 60),
                SizedBox(
                  width: 230,
                  child: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          );
                        },
                        child: const Text(
                          'Log In',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(height: 35),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CreateAccountPage(),
                            ),
                          );
                        },
                        child: const Text(
                          'Create Account',
                          style: TextStyle(fontSize: 20),
                          ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
