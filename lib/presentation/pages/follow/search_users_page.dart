import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/follow_repository.dart';
import '../../widgets/follow_button.dart';
import '../profile/public_profile_page.dart';

class SearchUsersPage extends StatefulWidget {
  const SearchUsersPage({super.key});

  @override
  State<SearchUsersPage> createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage> {
  final FollowRepository _followRepo = FollowRepository();
  final TextEditingController _searchController = TextEditingController();

  List<UserProfile> _searchResults = [];
  List<UserProfile> _suggestedUsers = [];
  bool _isSearching = false;
  bool _isLoadingSuggested = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggested() async {
    setState(() => _isLoadingSuggested = true);
    final users = await _followRepo.getSuggestedUsers(limit: 15);
    if (mounted) {
      setState(() {
        _suggestedUsers = users;
        _isLoadingSuggested = false;
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _query = '';
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _query = query;
      _isSearching = true;
    });

    final results = await _followRepo.searchUsers(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cerca utenti'),
      ),
      body: Column(
        children: [
          // Barra di ricerca
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Cerca per username...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // Contenuto
          Expanded(
            child: _query.isNotEmpty
                ? _buildSearchResults()
                : _buildSuggestedSection(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RISULTATI RICERCA
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Nessun utente trovato per "$_query"',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Prova con un username diverso',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) => _buildUserTile(_searchResults[index]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SUGGERIMENTI
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSuggestedSection() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Titolo
        Row(
          children: [
            const Icon(Icons.people_outline, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'Persone che potresti conoscere',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (!_isLoadingSuggested)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadSuggested,
                color: AppColors.textMuted,
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_isLoadingSuggested)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_suggestedUsers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.group_off, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'Nessun suggerimento al momento',
                  style: TextStyle(color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Cerca utenti con la barra in alto',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._suggestedUsers.map((user) => _buildUserTile(user)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TILE UTENTE
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildUserTile(UserProfile user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublicProfilePage(
                userId: user.id,
                username: user.username,
              ),
            ),
          );
        },
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
              ? NetworkImage(user.avatarUrl!)
              : null,
          child: user.avatarUrl == null || user.avatarUrl!.isEmpty
              ? Text(
                  user.initial,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                )
              : null,
        ),
        title: Text(
          user.username,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: user.bio != null && user.bio!.isNotEmpty
            ? Text(
                user.bio!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              )
            : Text(
                'Livello ${user.level}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
        trailing: FollowButton(
          targetUserId: user.id,
          compact: true,
        ),
      ),
    );
  }
}
