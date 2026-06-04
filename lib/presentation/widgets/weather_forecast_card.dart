import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/weather_service.dart';
import '../../data/models/weather_data.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/extensions/l10n_extension.dart';

/// Card che mostra meteo attuale + forecast 5 giorni per una location.
///
/// ```dart
/// WeatherForecastCard(lat: trail.startLat, lng: trail.startLng)
/// ```
class WeatherForecastCard extends StatefulWidget {
  final double lat;
  final double lng;

  const WeatherForecastCard({
    super.key,
    required this.lat,
    required this.lng,
  });

  @override
  State<WeatherForecastCard> createState() => _WeatherForecastCardState();
}

class _WeatherForecastCardState extends State<WeatherForecastCard> {
  final WeatherService _service = WeatherService();
  WeatherData? _weather;
  bool _isLoading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = false;
    });

    final data = await _service.getForecast(widget.lat, widget.lng);
    if (!mounted) return;

    setState(() {
      _weather = data;
      _isLoading = false;
      _error = data == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error || _weather == null)
              _buildError()
            else ...[
              _buildCurrent(_weather!.current),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildForecast(_weather!.daily),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.cloud, size: 20, color: AppColors.info),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Previsioni meteo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_isLoading && !_error)
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () {
              WeatherService.clearCache();
              _load();
            },
            tooltip: 'Aggiorna',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 20, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Meteo non disponibile',
              style: TextStyle(color: context.textMuted, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrent(CurrentWeather current) {
    return Row(
      children: [
        Icon(current.icon, size: 56, color: AppColors.info),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${current.temperature.round()}°C',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                current.description,
                style: TextStyle(
                  fontSize: 14,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _miniStat(
                    Icons.water_drop_outlined,
                    '${current.humidity.round()}%',
                  ),
                  const SizedBox(width: 12),
                  _miniStat(
                    Icons.air,
                    '${current.windSpeed.round()} km/h',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: context.textMuted),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
      ],
    );
  }

  Widget _buildForecast(List<DailyForecast> daily) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: daily.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => _dayTile(daily[index], index == 0),
      ),
    );
  }

  Widget _dayTile(DailyForecast day, bool isToday) {
    const months = ['Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu', 'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'];
    const weekdays = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
    final label = isToday ? 'Oggi' : weekdays[day.date.weekday - 1];

    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: isToday ? AppColors.info.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isToday ? AppColors.info.withValues(alpha: 0.3) : Colors.grey.shade200,
        ),
      ),
      // FittedBox garantisce che i contenuti non straccino mai il bounding
      // box anche con accessibility font più grandi (causava RenderFlex
      // overflow su alcuni device). In condizioni normali la scala è 1.0.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isToday ? AppColors.info : context.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.date.day} ${months[day.date.month - 1]}',
              style: TextStyle(fontSize: 9, color: context.textMuted),
            ),
            const SizedBox(height: 4),
            Icon(day.icon, size: 22, color: AppColors.info),
            const SizedBox(height: 4),
            Text(
              '${day.tempMax.round()}° / ${day.tempMin.round()}°',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
            if (day.precipitationMm > 0) ...[
              const SizedBox(height: 2),
              Text(
                '${day.precipitationMm.toStringAsFixed(1)} mm',
                style: const TextStyle(fontSize: 9, color: AppColors.info),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
