import 'package:flutter/material.dart';

/// Tipo di manovra (mappato dai `type` numerici di ORS).
///
/// Riferimento: https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/instructions
enum ManeuverType {
  turnLeft,
  turnRight,
  turnSharpLeft,
  turnSharpRight,
  turnSlightLeft,
  turnSlightRight,
  straight,
  enterRoundabout,
  exitRoundabout,
  uturn,
  depart,
  arrive,
  keepLeft,
  keepRight,
  unknown;

  /// Costruisce dal numero type ORS.
  static ManeuverType fromOrsType(int? type) {
    switch (type) {
      case 0:
        return ManeuverType.turnLeft;
      case 1:
        return ManeuverType.turnRight;
      case 2:
        return ManeuverType.turnSharpLeft;
      case 3:
        return ManeuverType.turnSharpRight;
      case 4:
        return ManeuverType.turnSlightLeft;
      case 5:
        return ManeuverType.turnSlightRight;
      case 6:
        return ManeuverType.straight;
      case 7:
        return ManeuverType.enterRoundabout;
      case 8:
        return ManeuverType.exitRoundabout;
      case 9:
        return ManeuverType.uturn;
      case 10:
        return ManeuverType.depart;
      case 11:
        return ManeuverType.arrive;
      case 12:
        return ManeuverType.keepLeft;
      case 13:
        return ManeuverType.keepRight;
      default:
        return ManeuverType.unknown;
    }
  }

  /// Testo italiano dell'azione senza distanza (es. "Svolta a sinistra").
  String get italianAction {
    switch (this) {
      case ManeuverType.turnLeft:
        return 'Svolta a sinistra';
      case ManeuverType.turnRight:
        return 'Svolta a destra';
      case ManeuverType.turnSharpLeft:
        return 'Svolta bruscamente a sinistra';
      case ManeuverType.turnSharpRight:
        return 'Svolta bruscamente a destra';
      case ManeuverType.turnSlightLeft:
        return 'Leggera svolta a sinistra';
      case ManeuverType.turnSlightRight:
        return 'Leggera svolta a destra';
      case ManeuverType.straight:
        return 'Prosegui dritto';
      case ManeuverType.enterRoundabout:
        return 'Entra nella rotatoria';
      case ManeuverType.exitRoundabout:
        return 'Esci dalla rotatoria';
      case ManeuverType.uturn:
        return 'Fai inversione a U';
      case ManeuverType.depart:
        return 'Parti';
      case ManeuverType.arrive:
        return 'Sei arrivato a destinazione';
      case ManeuverType.keepLeft:
        return 'Mantieni la sinistra';
      case ManeuverType.keepRight:
        return 'Mantieni la destra';
      case ManeuverType.unknown:
        return 'Prosegui';
    }
  }

  /// Frase completa "Tra 200 metri, svolta a sinistra".
  String instructionWithDistance(double meters) {
    if (this == ManeuverType.arrive) return italianAction;
    if (this == ManeuverType.depart) return italianAction;
    final distStr = _formatDistance(meters);
    if (meters < 60) {
      return italianAction;
    }
    return 'Tra $distStr, ${italianAction.toLowerCase()}';
  }

  IconData get icon {
    switch (this) {
      case ManeuverType.turnLeft:
      case ManeuverType.turnSharpLeft:
      case ManeuverType.turnSlightLeft:
        return Icons.turn_left;
      case ManeuverType.turnRight:
      case ManeuverType.turnSharpRight:
      case ManeuverType.turnSlightRight:
        return Icons.turn_right;
      case ManeuverType.straight:
        return Icons.straight;
      case ManeuverType.enterRoundabout:
      case ManeuverType.exitRoundabout:
        return Icons.roundabout_left;
      case ManeuverType.uturn:
        return Icons.u_turn_left;
      case ManeuverType.depart:
        return Icons.play_arrow;
      case ManeuverType.arrive:
        return Icons.flag;
      case ManeuverType.keepLeft:
        return Icons.fork_left;
      case ManeuverType.keepRight:
        return Icons.fork_right;
      case ManeuverType.unknown:
        return Icons.navigation;
    }
  }
}

String _formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Singolo step di navigazione derivato da ORS.
class NavigationStep {
  final int index;
  final ManeuverType maneuver;
  final double distance; // lunghezza step in metri
  final int wayPointStart; // indice polyline iniziale
  final int wayPointEnd; // indice polyline finale (manovra qui)
  final String? streetName;

  const NavigationStep({
    required this.index,
    required this.maneuver,
    required this.distance,
    required this.wayPointStart,
    required this.wayPointEnd,
    this.streetName,
  });
}
