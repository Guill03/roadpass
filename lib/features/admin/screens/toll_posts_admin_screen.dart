import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/toll_post.dart';
import '../../../services/toll_catalog_service.dart';

class TollPostsAdminScreen extends StatefulWidget {
  const TollPostsAdminScreen({super.key, required this.catalogService});

  final TollCatalogServiceBase catalogService;

  @override
  State<TollPostsAdminScreen> createState() => _TollPostsAdminScreenState();
}

class _TollPostsAdminScreenState extends State<TollPostsAdminScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<TollPost> _posts = const [];
  TollPost? _editingPost;

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await widget.catalogService.getTollPosts(includeInactive: true);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _resetForm() {
    _editingPost = null;
    _codeController.clear();
    _nameController.clear();
    _locationController.clear();
    _isActive = true;
    _error = null;
    if (mounted) setState(() {});
  }

  void _fillForm(TollPost post) {
    _editingPost = post;
    _codeController.text = post.code;
    _nameController.text = post.name;
    _locationController.text = post.location;
    _isActive = post.isActive;
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      if (_editingPost == null) {
        await widget.catalogService.createTollPost(
          code: _codeController.text,
          name: _nameController.text,
          location: _locationController.text,
        );
      } else {
        await widget.catalogService.updateTollPost(
          _editingPost!.id,
          code: _codeController.text,
          name: _nameController.text,
          location: _locationController.text,
          isActive: _isActive,
        );
      }
      _resetForm();
      await _load();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _editingPost == null
                            ? 'Ajouter un poste de péage'
                            : 'Modifier le poste',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
                      const Spacer(),
                      if (_editingPost != null)
                        TextButton.icon(
                          onPressed: _resetForm,
                          icon: const Icon(Icons.close),
                          label: const Text('Annuler'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codeController,
                          decoration: const InputDecoration(labelText: 'Code'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Le code est obligatoire.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Nom'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Le nom est obligatoire.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: 'Localisation'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'La localisation est obligatoire.'
                        : null,
                  ),
                  if (_editingPost != null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Poste actif'),
                      value: _isActive,
                      onChanged: (value) => setState(() => _isActive = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(_editingPost == null ? 'Ajouter' : 'Enregistrer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          ..._posts.map(
            (post) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(
                  Icons.location_on_outlined,
                  color: post.isActive ? AppTheme.navy : Colors.grey,
                ),
                title: Text('${post.code} — ${post.name}'),
                subtitle: Text(post.location),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      label: Text(post.isActive ? 'Actif' : 'Inactif'),
                      backgroundColor: post.isActive
                          ? Colors.green.shade50
                          : Colors.grey.shade200,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _fillForm(post),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
