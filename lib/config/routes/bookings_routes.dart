import '../api_config.dart';



class BookingsRoutes {

  BookingsRoutes._();



  static const String create = '/booking/create';

  static const String getFree = '/booking/get-free';

  static const String _getPrefix = '/booking/get/';

  static const String _updatePrefix = '/booking/update/';

  static const String _deletePrefix = '/booking/delete/';



  static String get createUrl => '${ApiConfig.baseUrl}$create';

  static String get getFreeUrl => '${ApiConfig.baseUrl}$getFree';



  static String getByIdUrl(int bookingId) => '${ApiConfig.baseUrl}$_getPrefix$bookingId';



  static String getByUserUrl(String userId) => '${ApiConfig.baseUrl}$_getPrefix$userId/user';



  static String updateUrl(int bookingId) => '${ApiConfig.baseUrl}$_updatePrefix$bookingId';



  static String deleteUrl(int bookingId) => '${ApiConfig.baseUrl}$_deletePrefix$bookingId';

}


