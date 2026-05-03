import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/allowed_countries.dart';
import '../services/ip_country_service.dart';
import '../theme/app_colors.dart';

/// Phone input with a country code dropdown (flag + dial code) on the
/// left and a local-number text field on the right.
///
/// Emits fully-qualified E.164 numbers via [onChanged] (e.g.
/// `+212612345678`). The dial code defaults to Morocco and is upgraded
/// to the user's detected country via [IpCountryService] on first
/// mount, unless [initialE164] was provided.
class CountryPhoneField extends StatefulWidget {
  const CountryPhoneField({
    super.key,
    this.initialE164,
    this.onChanged,
    this.hintText = '612345678',
    this.enabled = true,
    this.autofocus = false,
  });

  /// Pre-existing number (e.g. loaded from Firestore).
  /// Accepted formats: `+212612345678`, `212612345678`, `0612345678`.
  final String? initialE164;

  /// Emitted on every change. Returns null if the local part is empty.
  final ValueChanged<String?>? onChanged;

  final String hintText;
  final bool enabled;
  final bool autofocus;

  @override
  State<CountryPhoneField> createState() => _CountryPhoneFieldState();
}

class _CountryPhoneFieldState extends State<CountryPhoneField> {
  final TextEditingController _numberController = TextEditingController();
  Country _country = kDefaultCountry;
  bool _userChangedCountry = false;

  @override
  void initState() {
    super.initState();

    // Parse the existing number if any — this takes precedence over
    // the IP detection (the saved country is the user's truth).
    if (widget.initialE164 != null && widget.initialE164!.isNotEmpty) {
      _applyInitial(widget.initialE164!);
    } else {
      // Fire IP detection in the background.
      IpCountryService.detect().then((detected) {
        if (!mounted || _userChangedCountry || detected == null) return;
        setState(() => _country = detected);
        _emit();
      });
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _applyInitial(String raw) {
    // Normalize to digits-only then try to match a known dial code.
    String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);

    // Try each allowed country's dial code as a prefix. Longest first
    // to avoid matching '+1' when the number is actually from a longer
    // code accidentally starting with '1'.
    final sorted = [...kAllowedCountries]
      ..sort((a, b) => b.dial.length.compareTo(a.dial.length));
    for (final c in sorted) {
      final dialDigits = c.dial.substring(1); // strip '+'
      if (digits.startsWith(dialDigits)) {
        _country = c;
        _numberController.text = digits.substring(dialDigits.length);
        return;
      }
    }

    // Fall back: assume Morocco local ("0612345678" → "612345678").
    if (digits.startsWith('0')) digits = digits.substring(1);
    _numberController.text = digits;
  }

  void _emit() {
    final local = _numberController.text.replaceAll(RegExp(r'\D'), '');
    if (local.isEmpty) {
      widget.onChanged?.call(null);
    } else {
      widget.onChanged?.call('${_country.dial}$local');
    }
  }

  void _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CountryPickerSheet(selected: _country),
    );
    if (picked != null && mounted) {
      setState(() {
        _country = picked;
        _userChangedCountry = true;
      });
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondary50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: widget.enabled ? _pickCountry : null,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_country.flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    _country.dial,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.secondary500),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.secondary200),
          Expanded(
            child: TextField(
              controller: _numberController,
              keyboardType: TextInputType.phone,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                // Strip a leading zero if the user typed the local
                // "0XXXXXXXXX" format (Morocco/France convention).
                if (v.startsWith('0') && v.length > 1) {
                  _numberController.text = v.substring(1);
                  _numberController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _numberController.text.length),
                  );
                }
                _emit();
              },
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(
                  color: AppColors.secondary300,
                  fontSize: 13,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.selected});
  final Country selected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  List<Country> get _filtered {
    if (_query.isEmpty) return kAllowedCountries;
    final q = _query.toLowerCase();
    return kAllowedCountries
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.dial.contains(q) ||
            c.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un pays',
                    prefixIcon: const Icon(Icons.search, color: AppColors.secondary400),
                    filled: true,
                    fillColor: AppColors.secondary50,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final c = _filtered[i];
                    final isSelected = c.code == widget.selected.code;
                    return ListTile(
                      leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(c.name),
                      trailing: Text(
                        c.dial,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.brand600 : AppColors.secondary500,
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor: AppColors.brand50,
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
