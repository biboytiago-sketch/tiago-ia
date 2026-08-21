import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BookmakerConfig {
  final String id;
  final String name;
  final String? appScheme;
  final String webUrl;
  final bool supportsDirectCouponImport;
  final IconData icon;
  final Color accentColor;

  const BookmakerConfig({
    required this.id,
    required this.name,
    required this.webUrl,
    this.appScheme,
    this.supportsDirectCouponImport = false,
    required this.icon,
    required this.accentColor,
  });
}

const List<BookmakerConfig> SUPPORTED_BOOKMAKERS = <BookmakerConfig>[
  BookmakerConfig(
    id: 'bet365',
    name: 'Bet365',
    appScheme: 'bet365://',
    webUrl: 'https://www.bet365.com/#/HO/',
    icon: Icons.sports_soccer,
    accentColor: Color(0xFF00703C),
  ),
  BookmakerConfig(
    id: 'sportingbet',
    name: 'Sportingbet',
    appScheme: 'sportingbet://',
    webUrl: 'https://www.sportingbet.com.br/',
    icon: Icons.casino,
    accentColor: Color(0xFFFFC107),
  ),
  BookmakerConfig(
    id: 'betano',
    name: 'Betano',
    appScheme: 'betano://',
    webUrl: 'https://br.betano.com/',
    supportsDirectCouponImport: true,
    icon: Icons.auto_awesome,
    accentColor: Color(0xFF21C100),
  ),
  BookmakerConfig(
    id: 'pixbet',
    name: 'Pixbet',
    appScheme: 'pixbet://',
    webUrl: 'https://pixbet.com/',
    icon: Icons.pix,
    accentColor: Color(0xFF20B2AA),
  ),
  BookmakerConfig(
    id: 'kto',
    name: 'KTO',
    appScheme: 'kto://',
    webUrl: 'https://kto.com/',
    icon: Icons.diamond,
    accentColor: Color(0xFFE53935),
  ),
  BookmakerConfig(
    id: '1xbet',
    name: '1xBet',
    appScheme: 'onexbet://',
    webUrl: 'https://1xbet.com/',
    icon: Icons.star,
    accentColor: Color(0xFF1976D2),
  ),
  BookmakerConfig(
    id: 'stake',
    name: 'Stake',
    appScheme: 'stake://',
    webUrl: 'https://stake.com/',
    supportsDirectCouponImport: true,
    icon: Icons.savings,
    accentColor: Color(0xFF00B777),
  ),
];
