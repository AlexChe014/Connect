import 'package:connect/config/routes/user_routes.dart';
import 'package:connect/models/staff_user.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/paginated.dart';

class UsersRepository {
  UsersRepository._();
  static final UsersRepository instance = UsersRepository._();

  /// Первая страница с фильтрами `q` и `dep`, либо полный URL следующей страницы.
  Future<Paginated<StaffUser>> getPage({
    String? url,
    String? q,
    String? dep,
  }) async {
    final requestUrl = url ?? _buildFilterUrl(q: q, dep: dep, page: 1);
    final decoded = await ApiClient.instance.get(requestUrl);

    return ApiPaginatedEnvelope.unwrapPaginated<StaffUser>(
      decoded,
      defaultErrorMessage: 'Не удалось получить список сотрудников',
      mapItem: StaffUser.fromJson,
    );
  }

  String _buildFilterUrl({String? q, String? dep, required int page}) {
    final base = Uri.parse(UserRoutes.getByFilterUrl);
    final params = Map<String, String>.from(base.queryParameters);
    params['page'] = page.toString();
    final qt = q?.trim();
    final dt = dep?.trim();
    if (qt != null && qt.isNotEmpty) {
      params['q'] = qt;
    } else {
      params.remove('q');
    }
    if (dt != null && dt.isNotEmpty) {
      params['dep'] = dt;
    } else {
      params.remove('dep');
    }
    return base.replace(queryParameters: params).toString();
  }
}
