import 'package:cloud_functions/cloud_functions.dart';

class ReportRepository {
  Future<void> reportEntry(String entryId, String reason) async {
    await FirebaseFunctions.instance
        .httpsCallable('reportContent')
        .call({'entryId': entryId, 'reason': reason});
  }
}
