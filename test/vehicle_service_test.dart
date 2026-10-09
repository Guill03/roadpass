import 'package:flutter_test/flutter_test.dart';
import 'package:roadpass/models/vehicle.dart';
import 'package:roadpass/services/vehicle_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Vehicle.fromMap', () {
    test('mappe les champs du schéma véhicule', () {
      final vehicle = Vehicle.fromMap({
        'id': 'vehicle-1',
        'user_id': 'user-1',
        'brand': 'Toyota',
        'model': 'Corolla',
        'registration_number': 'AB 123 CD',
        'category': 'Voiture légère',
        'category_id': 'category-1',
        'is_active': true,
        'created_at': '2025-01-01T12:00:00Z',
        'updated_at': '2025-01-02T12:00:00Z',
      });

      expect(vehicle.id, 'vehicle-1');
      expect(vehicle.userId, 'user-1');
      expect(vehicle.registrationNumber, 'AB 123 CD');
      expect(vehicle.categoryId, 'category-1');
      expect(vehicle.isActive, isTrue);
      expect(vehicle.createdAt, DateTime.parse('2025-01-01T12:00:00Z'));
    });
  });

  group('VehicleService sans session', () {
    late SupabaseClient client;
    late VehicleService service;

    setUp(() {
      client = SupabaseClient('http://127.0.0.1:54321', 'test-key');
      service = VehicleService(client: client);
    });

    tearDown(() => client.dispose());

    test('refuse les opérations sans appeler la base', () async {
      await expectLater(
        service.getMyVehicles(),
        throwsA(isA<VehicleServiceException>()),
      );
      await expectLater(
        service.getVehicle('vehicle-1'),
        throwsA(isA<VehicleServiceException>()),
      );
      await expectLater(
        service.updateVehicle('vehicle-1', brand: 'Toyota'),
        throwsA(isA<VehicleServiceException>()),
      );
      await expectLater(
        service.deactivateVehicle('vehicle-1'),
        throwsA(isA<VehicleServiceException>()),
      );
    });
  });
}
