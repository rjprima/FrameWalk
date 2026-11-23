import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/profile_provider.dart';
import '../../backend/services/auth_service.dart';

class AccountPage extends StatelessWidget {
  final AuthService? authService;

  const AccountPage({super.key, this.authService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context.watch<ProfileProvider>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page header: matches HomePage positioning.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text('FrameWalk', style: theme.textTheme.headlineMedium),
            ),

            // Remaining account content.
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

                  // Account statistics.
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

  Widget _buildProfileInfo(String username, String email, ThemeData theme) {
    // Account statistics.
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFFE2E9DF),
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
