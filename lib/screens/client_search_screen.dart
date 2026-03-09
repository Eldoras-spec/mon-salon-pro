import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../models/salon_model.dart';
import 'client_salon_profile_screen.dart';

class ClientSearchScreen extends StatefulWidget {
  const ClientSearchScreen({super.key});

  @override
  State<ClientSearchScreen> createState() => _ClientSearchScreenState();
}

class _ClientSearchScreenState extends State<ClientSearchScreen> {
  final _db = DatabaseService();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  List<SalonModel> _results = [];
  bool _loading = false;
  bool _hasSearched = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onChanged);
    // Auto-focus when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final results = await _db.searchSalons(q);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: AppColors.secondary700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.secondary50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.secondary200),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.secondary900,
                ),
                decoration: InputDecoration(
                  hintText: 'Salon, service, ville...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: AppColors.secondary400,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.secondary400, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () => _searchController.clear(),
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.secondary400, size: 18),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brand500),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 64, color: AppColors.secondary200),
            const SizedBox(height: 16),
            Text(
              'Rechercher un salon',
              style: GoogleFonts.dmSans(
                fontSize: 20,
                color: AppColors.secondary400,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Par nom, ville ou catégorie',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.secondary400,
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined,
                size: 64, color: AppColors.secondary200),
            const SizedBox(height: 16),
            Text(
              'Aucun résultat',
              style: GoogleFonts.dmSans(
                fontSize: 20,
                color: AppColors.secondary400,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Essayez un autre nom ou ville',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.secondary400,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildSalonCard(_results[index]),
    );
  }

  Widget _buildSalonCard(SalonModel salon) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClientSalonProfileScreen(salon: salon),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: salon.images.isNotEmpty
                  ? Image.network(
                      salon.images.first,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      salon.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondary900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 12, color: AppColors.secondary400),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            salon.city,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.secondary500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: AppColors.gold500),
                        const SizedBox(width: 3),
                        Text(
                          salon.rating.toStringAsFixed(1),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondary700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${salon.reviewCount})',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.secondary400,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            salon.category,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded,
                  color: AppColors.secondary300, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 90,
      height: 90,
      color: AppColors.secondary100,
      child: const Icon(Icons.storefront_outlined,
          color: AppColors.secondary300, size: 32),
    );
  }
}
