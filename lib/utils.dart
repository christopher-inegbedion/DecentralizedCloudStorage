import 'package:intl/intl.dart';

String convertTimestampToDate(int value) {
  var date = DateTime.fromMillisecondsSinceEpoch(value);
  var d12 = DateFormat('EEE, MM-dd-yyyy, hh:mm:ss a').format(date);
  return d12;
}
