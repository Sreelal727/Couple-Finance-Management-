import 'package:flutter/material.dart';

/// Icons are stored by string key so they survive sync between app versions.
class CategoryIcons {
  CategoryIcons._();

  static const map = <String, IconData>{
    'home': Icons.home_rounded,
    'grocery': Icons.local_grocery_store_rounded,
    'restaurant': Icons.restaurant_rounded,
    'transport': Icons.directions_bus_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'bolt': Icons.bolt_rounded,
    'wifi': Icons.wifi_rounded,
    'household': Icons.chair_rounded,
    'health': Icons.medical_services_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'subscriptions': Icons.subscriptions_rounded,
    'movie': Icons.movie_rounded,
    'gift': Icons.card_giftcard_rounded,
    'travel': Icons.flight_takeoff_rounded,
    'spa': Icons.spa_rounded,
    'investment': Icons.trending_up_rounded,
    'other': Icons.category_rounded,
    'salary': Icons.payments_rounded,
    'work': Icons.work_rounded,
    'interest': Icons.savings_rounded,
    'savings': Icons.savings_rounded,
    'coffee': Icons.coffee_rounded,
    'pet': Icons.pets_rounded,
    'education': Icons.school_rounded,
    'baby': Icons.child_care_rounded,
    'car': Icons.directions_car_rounded,
    'bike': Icons.two_wheeler_rounded,
    'phone': Icons.smartphone_rounded,
    'laundry': Icons.local_laundry_service_rounded,
    'temple': Icons.temple_hindu_rounded,
    'beach': Icons.beach_access_rounded,
    'celebration': Icons.celebration_rounded,
    'fitness': Icons.fitness_center_rounded,
    'loan': Icons.account_balance_rounded,
    'insurance': Icons.shield_rounded,
    'star': Icons.star_rounded,
  };

  static IconData of(String? key) => map[key] ?? Icons.category_rounded;
}
