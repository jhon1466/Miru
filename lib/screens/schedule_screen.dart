import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/schedule.dart';
import '../providers/anime_provider.dart';
import '../widgets/anime_poster_image.dart';
import 'detail_screen.dart';

class ScheduleScreen extends StatefulWidget {
  final bool embedded;

  const ScheduleScreen({super.key, this.embedded = false});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  WeeklySchedule? _schedule;
  bool _loading = false;
  String? _error;
  late String _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = scheduleDayForDate(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSchedule());
  }

  Future<void> _loadSchedule() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final domain = context.read<AnimeProvider>().selectedProviderDomain;
      final data = await ApiClient.getWeeklySchedule(
        domain: domain.isEmpty ? null : domain,
      );
      if (!mounted) return;
      setState(() {
        _schedule = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<ScheduleEntry> get _visibleItems {
    if (_schedule == null) return [];
    return _schedule!.itemsForDay(_selectedDay);
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    final now = DateTime.now();
    final timeLabel =
        '${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'pm' : 'am'}';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Horario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadSchedule,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSchedule,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                      ),
                      child: const Text(
                        'Los horarios son referenciales y pueden variar.',
                        style: TextStyle(color: Colors.amber, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Spacer(),
                        Text(
                          'Hora local: $timeLabel',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: scheduleDayLabels.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final day = scheduleDayLabels[index];
                          final selected = day == _selectedDay;
                          return FilterChip(
                            label: Text(day),
                            selected: selected,
                            onSelected: (_) => setState(() => _selectedDay = day),
                            selectedColor: AppTheme.primaryColor.withValues(alpha: 0.25),
                            checkmarkColor: AppTheme.primaryColor,
                            labelStyle: TextStyle(
                              color: selected ? AppTheme.primaryColor : AppTheme.textSecondary,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (_loading && _schedule == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
              )
            else if (_error != null && _schedule == null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadSchedule, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                ),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No hay emisiones para $_selectedDay',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _ScheduleCard(entry: items[index]),
                    childCount: items.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final ScheduleEntry entry;

  const _ScheduleCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (entry.url.isEmpty) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailScreen(
                animeUrl: entry.url,
                animeTitle: entry.title,
                animeImage: entry.image,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimePosterImage(
                    imageUrl: entry.image,
                    fit: BoxFit.cover,
                  ),
                  if (entry.displayTime.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entry.displayTime,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (entry.episodeNumber != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ep. ${entry.episodeNumber!.toStringAsFixed(entry.episodeNumber! % 1 == 0 ? 0 : 1)}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
