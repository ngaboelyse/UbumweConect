import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

enum AvatarSize { small, medium, large, xlarge }

class UserAvatar extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final bool isOnline;
  final AvatarSize size;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.displayName,
    this.avatarUrl,
    this.isOnline = false,
    this.size = AvatarSize.medium,
    this.onTap,
  });

  double get _radius {
    switch (size) {
      case AvatarSize.small: return 16;
      case AvatarSize.medium: return 24;
      case AvatarSize.large: return 32;
      case AvatarSize.xlarge: return 48;
    }
  }

  double get _indicatorSize {
    switch (size) {
      case AvatarSize.small: return 8;
      case AvatarSize.medium: return 11;
      case AvatarSize.large: return 14;
      case AvatarSize.xlarge: return 18;
    }
  }

  String get _initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          CircleAvatar(
            radius: _radius,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl!) : null,
            child: avatarUrl == null
                ? Text(
                    _initials,
                    style: TextStyle(
                      fontSize: _radius * 0.65,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontFamily: 'Poppins',
                    ),
                  )
                : null,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: _indicatorSize,
                height: _indicatorSize,
                decoration: BoxDecoration(
                  color: AppColors.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
