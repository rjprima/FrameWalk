import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/profile_provider.dart';
import '../../backend/services/auth_service.dart';

// the account page, displaying the user's information and statistics and a button to log out
class AccountPage extends StatelessWidget {
  final AuthService? authService; // the auth service to handle logging out

  const AccountPage({super.key, this.authService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // gets the theme of this BuildContext
    final profile = context.watch<ProfileProvider>(); // only watching the provider because only need to keep up with changes, not make any

    return SafeArea(
      // avoids OS interfaces, like the island on iphones
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // left align everything
          children: [
            // Page header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text('FrameWalk', style: theme.textTheme.headlineMedium),
            ),

            // Remaining account content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),

                  // Profile information.
                  _buildProfileInfo(
                    profile.username ?? "Username",
                    profile.email ?? '',
                    theme,
                  ),

                  const SizedBox(height: 40),

                  // Account statistics
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          icon: Icons.photo_outlined,
                          label: 'Photos',
                          value: profile.photosUploaded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          icon: Icons.map_outlined,
                          label: 'Routes',
                          value: profile.routesCompleted,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 44),

                  // Log out button.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => (authService ?? AuthService()).logOut(),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// builds the profile info at the top of the page
  /// displays a placeholder circular avatar, the user's username, and user's email
  Widget _buildProfileInfo(String username, String email, ThemeData theme) {
    return Row(
      children: [
        // placeholder avatar
        CircleAvatar(
          backgroundColor: const Color(0xFFE2E9DF), // TODO: add this light green to app theme, it's used in activty page and route filter chips too
          radius: 27,
          child: const Icon(Icons.person_outline, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Email: $email',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // builds a card displaying an account statistic
  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int value,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
