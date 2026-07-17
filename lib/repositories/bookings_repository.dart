import 'package:connect/config/routes/bookings_routes.dart';
import 'package:connect/config/routes/objects_routes.dart';

import 'package:connect/models/bookings/booking_addition.dart';
import 'package:connect/models/bookings/booking_detail.dart';

import 'package:connect/models/bookings/bookable_object.dart';

import 'package:connect/models/bookings/create_booking_request.dart';

import 'package:connect/models/bookings/update_booking_request.dart';

import 'package:connect/models/bookings/user_booking.dart';

import 'package:connect/services/api_client.dart';

import 'package:connect/services/api_envelope.dart';



class BookingsRepository {

  BookingsRepository._();

  static final BookingsRepository instance = BookingsRepository._();

  /// Список дополнений к брони (`GET /objects/addition/get`).
  Future<List<BookingAddition>> getAdditions() async {
    final decoded = await ApiClient.instance.get(ObjectsRoutes.additionsUrl);
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить список дополнений',
    );
    return list
        .whereType<Map>()
        .map((e) => BookingAddition.fromJson(e.cast<String, dynamic>()))
        .where((a) => a.id > 0)
        .toList();
  }

  /// Создание обычной или повторяющейся брони (`POST /booking/create`).
  Future<BookingDetail> createBooking(CreateBookingRequest request) async {

    final decoded = await ApiClient.instance.postForm(

      BookingsRoutes.createUrl,

      fields: request.toFormEntries(),

    );

    final data = ApiEnvelope.unwrapDataMap(

      decoded,

      defaultErrorMessage: 'Не удалось создать бронирование',

    );

    return BookingDetail.fromJson(data);

  }



  /// Обновление брони (`POST /booking/update/{id}`).

  Future<BookingDetail> updateBooking({

    required int bookingId,

    required UpdateBookingRequest request,

  }) async {

    final fields = request.toFormEntries();

    if (fields.isEmpty) {

      throw ApiException(400, 'Нет полей для обновления бронирования');

    }



    final decoded = await ApiClient.instance.postForm(

      BookingsRoutes.updateUrl(bookingId),

      fields: fields,

    );

    final data = ApiEnvelope.unwrapDataMap(

      decoded,

      defaultErrorMessage: 'Не удалось обновить бронирование',

    );

    return BookingDetail.fromJson(data);

  }



  /// Удаление брони (`GET /booking/delete/{id}`).

  ///

  /// [deleteAll] — удалить всю серию повторяющихся броней (`delete_all=1`).

  Future<void> deleteBooking({

    required int bookingId,

    bool deleteAll = false,

  }) async {

    final decoded = await ApiClient.instance.get(

      BookingsRoutes.deleteUrl(bookingId),

      queryParameters: deleteAll ? const {'delete_all': '1'} : null,

    );

    ApiEnvelope.unwrapData(

      decoded,

      defaultErrorMessage: 'Не удалось удалить бронирование',

    );

  }



  /// Карточка брони по id (`GET /booking/get/{id}`).

  Future<BookingDetail> getBookingById(int bookingId) async {

    final decoded = await ApiClient.instance.get(BookingsRoutes.getByIdUrl(bookingId));

    final data = ApiEnvelope.unwrapDataMap(

      decoded,

      defaultErrorMessage: 'Не удалось получить бронирование',

    );

    return BookingDetail.fromJson(data);

  }



  Future<List<BookableObject>> getFreeObjects({

    required int modelType,

    required int datetimeStartSeconds,

    required int datetimeEndSeconds,

    required int spaceId,

    int? capacity,

    List<int> equipmentIds = const [],

  }) async {

    final url = _buildGetFreeUrl(

      modelType: modelType,

      datetimeStartSeconds: datetimeStartSeconds,

      datetimeEndSeconds: datetimeEndSeconds,

      spaceId: spaceId,

      capacity: capacity,

      equipmentIds: equipmentIds,

    );



    final decoded = await ApiClient.instance.get(url);

    final list = ApiEnvelope.unwrapDataList(

      decoded,

      defaultErrorMessage: 'Не удалось получить доступные объекты',

    );

    return list

        .whereType<Map>()

        .map((e) => BookableObject.fromJson(e.cast<String, dynamic>()))

        .where((o) => o.isActive)

        .toList();

  }



  Future<List<UserBooking>> getBookingsByUserForRange({

    required int userId,

    required int datetimeStartSeconds,

    required int datetimeEndSeconds,

  }) async {

    final url = _buildGetByUserUrl(

      userId: userId,

      datetimeStartSeconds: datetimeStartSeconds,

      datetimeEndSeconds: datetimeEndSeconds,

    );



    final decoded = await ApiClient.instance.get(url);

    final list = ApiEnvelope.unwrapDataList(

      decoded,

      defaultErrorMessage: 'Не удалось получить бронирования пользователя',

    );

    return list

        .whereType<Map>()

        .map((e) => UserBooking.fromJson(e.cast<String, dynamic>()))

        .toList();

  }



  String _buildGetFreeUrl({

    required int modelType,

    required int datetimeStartSeconds,

    required int datetimeEndSeconds,

    required int spaceId,

    int? capacity,

    required List<int> equipmentIds,

  }) {

    final baseUrl = BookingsRoutes.getFreeUrl;

    final pairs = <String, String>{

      'model_type': modelType.toString(),

      'datetime_start': datetimeStartSeconds.toString(),

      'datetime_end': datetimeEndSeconds.toString(),

      'space': spaceId.toString(),

      if (capacity != null) 'capacity': capacity.toString(),

    }.entries.map((e) => MapEntry(e.key, e.value)).toList();



    final extra = equipmentIds.map((id) => MapEntry('equipment[]', id.toString()));



    final query = <String>[

      ...pairs.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}'),

      ...extra.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}'),

    ].join('&');

    return query.isEmpty ? baseUrl : '$baseUrl?$query';

  }



  String _buildGetByUserUrl({

    required int userId,

    required int datetimeStartSeconds,

    required int datetimeEndSeconds,

  }) {

    final baseUrl = BookingsRoutes.getByUserUrl(userId.toString());

    final pairs = <String, String>{

      'datetime_start': datetimeStartSeconds.toString(),

      'datetime_end': datetimeEndSeconds.toString(),

    };



    final query = pairs.entries

        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')

        .join('&');

    return query.isEmpty ? baseUrl : '$baseUrl?$query';

  }

}


