// import 'package:flutter/material.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:roadpass/features/user/screens/vehicle_management_screen.dart';
// import 'package:roadpass/models/user.dart';
// import 'package:roadpass/models/vehicle.dart';
// import 'package:roadpass/models/vehicle_category.dart';
// import 'package:roadpass/services/auth_service.dart';
// import 'package:roadpass/services/vehicle_service.dart';

// class MockVehicleService extends VehicleServiceBase {
//   MockVehicleService({List<Vehicle> vehicles = const []})
//     : _vehicles = List.from(vehicles);

//   final List<Vehicle> _vehicles;

//   @override
//   Future<List<Vehicle>> getMyVehicles() async => List.from(_vehicles);

//   @override
//   Future<Vehicle> getVehicle(String id) async {
//     final vehicle = _vehicles.firstWhere(
//       (entry) => entry.id == id,
//       orElse: () => throw StateError('Not found'),
//     );
//     return vehicle;
//   }

//   @override
//   Future<Vehicle> createVehicle({
//     required String brand,
//     required String model,
//     required String registrationNumber,
//     required VehicleCategory category,
//   }) async {
//     final vehicle = Vehicle(
//       id: 'vehicle-${_vehicles.length + 1}',
//       userId: 'user-123',
//       brand: brand,
//       model: model,
//       registrationNumber: registrationNumber,
//       category: category,
//       isActive: true,
//       createdAt: DateTime.now(),
//       updatedAt: DateTime.now(),
//     );
//     _vehicles.add(vehicle);
//     return vehicle;
//   }

//   @override
//   Future<Vehicle> updateVehicle(
//     String id, {
//     String? brand,
//     String? model,
//     String? registrationNumber,
//     VehicleCategory? category,
//   }) async {
//     final index = _vehicles.indexWhere((vehicle) => vehicle.id == id);
//     if (index == -1) {
//       throw StateError('Not found');
//     }
//     final current = _vehicles[index];
//     final updated = current.copyWith(
//       brand: brand,
//       model: model,
//       registrationNumber: registrationNumber,
//       category: category,
//     );
//     _vehicles[index] = updated;
//     return updated;
//   }

//   @override
//   Future<Vehicle> deactivateVehicle(String id) async {
//     final index = _vehicles.indexWhere((vehicle) => vehicle.id == id);
//     if (index == -1) {
//       throw StateError('Not found');
//     }
//     final updated = _vehicles[index].copyWith(isActive: false);
//     _vehicles[index] = updated;
//     return updated;
//   }
// }

// void main() {
//   test('le modèle Vehicle infère correctement les champs depuis Supabase', () {
//     final vehicle = Vehicle.fromMap({
//       'id': 'a1',
//       'user_id': 'u1',
//       'brand': 'Toyota',
//       'model': 'Corolla',
//       'registration_number': 'CG 1234 AB',
//       'category': 'citadine',
//       'is_active': true,
//       'created_at': '2025-01-01T12:00:00+00:00',
//       'updated_at': '2025-01-02T12:00:00+00:00',
//     });

//     expect(vehicle.brand, 'Toyota');
//     expect(vehicle.isActive, isTrue);
//     expect(vehicle.registrationNumber, 'CG 1234 AB');
//   });

//   testWidgets('l’état vide affiche un appel à l’ajout', (tester) async {
//     final authService = _FakeAuthService();
//     final vehicleService = MockVehicleService();

//     await tester.pumpWidget(
//       MaterialApp(
//         home: VehicleManagementScreen(
//           catalogService: CatalogService(),
//           authService: authService,
//           vehicleService: vehicleService,
//         ),
//       ),
//     );
//     await tester.pumpAndSettle();

//     expect(find.text('Vous n’avez encore aucun véhicule.'), findsOneWidget);
//     expect(find.text('Ajouter un véhicule'), findsOneWidget);
//   });
// }

// class _FakeAuthService extends AuthService {
//   @override
//   RoadUser? get currentUser => const RoadUser(
//     id: 'user-123',
//     nom: 'Test',
//     prenom: 'User',
//     email: 'user@roadpass.test',
//     telephone: '+2250700000000',
//     role: UserRole.user,
//   );

//   @override
//   bool get isInitialized => true;

//   @override
//   Future<void> initialize() async {}

//   @override
//   Future<RoadUser> login(String email, String password) async => currentUser!;

//   @override
//   Future<RoadUser> register({
//     required String nom,
//     required String prenom,
//     required String email,
//     required String telephone,
//     required String password,
//   }) async => currentUser!;

//   @override
//   Future<RoadUser> professionalLogin(String email, String password) async =>
//       currentUser!;

//   @override
//   Future<RoadUser> createAgentAccount({
//     required String nom,
//     required String prenom,
//     required String email,
//     required String telephone,
//     required String password,
//   }) async => currentUser!;

//   @override
//   Future<RoadUser> updateProfile({
//     required String nom,
//     required String prenom,
//     required String email,
//     required String telephone,
//     String? password,
//   }) async => currentUser!;

//   @override
//   Future<void> logout() async {}
// }
