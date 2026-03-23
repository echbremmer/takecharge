import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../api/client.dart';
import '../main.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Uint8List? _avatarBytes;
  bool _loadingImage = true;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    try {
      final res = await ApiClient.instance.dio.get(
        '/api/profile/image',
        options: Options(responseType: ResponseType.bytes),
      );
      if (mounted && res.statusCode == 200) {
        setState(() => _avatarBytes = Uint8List.fromList(res.data));
      }
    } catch (_) {
      // No image yet
    } finally {
      if (mounted) setState(() => _loadingImage = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final form =
        FormData.fromMap({'image': MultipartFile.fromBytes(bytes, filename: picked.name)});
    try {
      await ApiClient.instance.postForm('/api/profile/image', form);
      if (mounted) setState(() => _avatarBytes = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final avatarSize = MediaQuery.of(context).size.width * 0.8;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          // Circular avatar
          GestureDetector(
            onTap: _pickAndUpload,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfaceNest,
                    image: _avatarBytes != null
                        ? DecorationImage(
                            image: MemoryImage(_avatarBytes!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _loadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : (_avatarBytes == null
                          ? Icon(Icons.person,
                              size: avatarSize * 0.4,
                              color: AppTheme.onSurfaceMuted)
                          : null),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary,
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (user != null)
            Text(
              user['username'] ?? '',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurface,
              ),
            ),

          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secondary,
                side: const BorderSide(color: AppTheme.secondary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              onPressed: _logout,
            ),
          ),
        ],
      ),
    );
  }
}
