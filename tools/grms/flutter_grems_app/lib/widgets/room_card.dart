import 'package:flutter/material.dart';
import '../models/room_models.dart';

class RoomCard extends StatelessWidget {
  static const double _cornerRadius = 10;
  static const double _topInset = 6;
  static const double _sideInset = 6;
  static const double _topIconSize = 20;
  static const double _serviceIconSize = 20;
  static const double _serviceStripHeight = 24;
  static const double _iconVerticalOffset = 5;
  static const double _roomNumberVerticalOffset = 1;

  final RoomData room;
  final bool showLighting;
  final bool showHVAC;
  final bool showRoomService;
  final VoidCallback? onCardTap;
  final VoidCallback? onLightingTap;
  final VoidCallback? onHVACTap;

  const RoomCard({
    super.key,
    required this.room,
    this.showLighting = true,
    this.showHVAC = true,
    this.showRoomService = true,
    this.onCardTap,
    this.onLightingTap,
    this.onHVACTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCardTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_cornerRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_cornerRadius),
                child: Container(
                  color: Colors.black.withOpacity(0.06),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          _getBackgroundImage(),
                          fit: BoxFit.contain,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                      // Top row: Lighting icon, room number, HVAC icon
                      Positioned(
                        top: _topInset,
                        left: _sideInset,
                        right: _sideInset,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: _topIconSize,
                              height: _topIconSize,
                              child: showLighting
                                  ? _buildClickableIcon(
                                      _getLightingIcon(),
                                      onLightingTap,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            Expanded(
                              child: Align(
                                alignment: const Alignment(0.2, 0),
                                child: Transform.translate(
                                  offset: const Offset(
                                    0,
                                    _roomNumberVerticalOffset,
                                  ),
                                  child: Text(
                                    room.number,
                                    style: _buildRoomNumberTextStyle(),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: _topIconSize,
                              height: _topIconSize,
                              child: showHVAC
                                  ? _buildClickableIcon(
                                      _getHVACIcon(),
                                      onHVACTap,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showRoomService)
            SizedBox(
              key: const ValueKey('room-service-strip'),
              height: _serviceStripHeight,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildServiceIcon(_getDndIcon()),
                  _buildServiceIcon(_getMurIcon()),
                  _buildServiceIcon(_getLaundryIcon()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClickableIcon(String asset, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Transform.translate(
          offset: const Offset(0, _iconVerticalOffset),
          child: Image.asset(asset, width: _topIconSize, height: _topIconSize),
        ),
      ),
    );
  }

  Widget _buildServiceIcon(String asset) {
    return Transform.translate(
      offset: const Offset(0, _iconVerticalOffset),
      child: Image.asset(
        asset,
        width: _serviceIconSize,
        height: _serviceIconSize,
        fit: BoxFit.contain,
      ),
    );
  }

  TextStyle _buildRoomNumberTextStyle() {
    return const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      shadows: [Shadow(color: Colors.black, blurRadius: 3)],
    );
  }

  String _getBackgroundImage() {
    const basePath = 'assets/images/room_status/';
    if (room.hasAlarm) {
      switch (room.status) {
        case RoomStatus.rentedOccupied:
          return '${basePath}redadamvaliz.png';
        case RoomStatus.rentedHK:
          return '${basePath}redhousekeeping.png';
        case RoomStatus.rentedVacant:
          return '${basePath}redvaliz.png';
        case RoomStatus.unrentedHK:
          return '${basePath}redhousekeeping.png';
        default:
          return '${basePath}onlyRed.png';
      }
    } else {
      switch (room.status) {
        case RoomStatus.rentedOccupied:
          return '${basePath}greenadamvaliz.png';
        case RoomStatus.rentedHK:
          return '${basePath}greenhousekeeping.png';
        case RoomStatus.rentedVacant:
          return '${basePath}greenvaliz.png';
        case RoomStatus.unrentedHK:
          return '${basePath}whitehousekeeping.png';
        default:
          return '${basePath}white.png';
      }
    }
  }

  String _getLightingIcon() {
    const basePath = 'assets/images/room_status/';
    return room.lightingOn
        ? '${basePath}LightingOn.png'
        : '${basePath}LightingOff.png';
  }

  String _getHVACIcon() {
    const basePath = 'assets/images/room_status/';
    switch (room.hvac) {
      case HvacStatus.cold:
        return '${basePath}HvacActiveCold.png';
      case HvacStatus.hot:
        return '${basePath}HvacActiveHot.png';
      default:
        return '${basePath}HvacActive.png';
    }
  }

  String _getDndIcon() {
    const basePath = 'assets/images/room_status/';
    return room.dnd == DndStatus.on
        ? '${basePath}dndyellow.png'
        : '${basePath}dnd.png';
  }

  String _getMurIcon() {
    const basePath = 'assets/images/room_status/';
    switch (room.mur) {
      case MurStatus.requested:
      case MurStatus.started:
        return '${basePath}muryellow.png';
      case MurStatus.delayed:
        return '${basePath}murDelayed.png';
      default:
        return '${basePath}mur.png';
    }
  }

  String _getLaundryIcon() {
    const basePath = 'assets/images/room_status/';
    switch (room.laundry) {
      case LaundryStatus.requested:
        return '${basePath}lndyellow.png';
      case LaundryStatus.delayed:
        return '${basePath}lndDelayed.png';
      default:
        return '${basePath}lnd.png';
    }
  }
}
