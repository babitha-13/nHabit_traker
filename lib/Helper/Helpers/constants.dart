import 'dart:convert';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

const String root = "/";
const String login = "/login";
const String dashboard = "/dashboard";
const String signUp = "/signup";
const String home = "/home";
const String splash = "/Splash";
const String changePassword = "/changepassword";
const String forgetPassword = "/forgotpassword";
const String transactions = "/transactions";

class Asset {
  static AssetName get string => AssetName();
  static AssetRoot get rootName => AssetRoot();
}

class AssetRoot {
  String get images => "assets/image/";
}

class AssetName {
  String get noPicturesIcon => prefixWithAssetRootName("no_pictures.png");
  String get aDateLogo => prefixWithAssetRootName("date.png");
  String get aLoginLogo => prefixWithAssetRootName("logo-white.png");
  String get aLogo => prefixWithAssetRootName("logo.png");
  String get aNoData => prefixWithAssetRootName("reName.png");
  String get pdf => prefixWithAssetRootName("pdf.png");
}

String prefixWithAssetRootName(String name) {
  return "${Asset.rootName.images}$name";
}

class Content {
  static ScreenName get screen => ScreenName();
  static String update(String name) {
    return name;
  }
}

class SharedPreference {
  static SharedPreferenceConstant get name => SharedPreferenceConstant();
}

class SharedPreferenceConstant {
  String get sApplicationStarted => "initiated";
  String get sEmailID => "EmailID";
  String get sPassword => "Password";
  String get sLoggedIn => "isLoggedIn";
  String get sUserDetails => "data";
  String get sUserFirst => "first";
  String get sTabBarHeight => 'TabBarHeight';
}

class ScreenName {
  Constant get language => Constant();
}

class Constant {
  double get width => 60;
  double get height => 30;
}

typedef StructBuilder<T> = T Function(Map<String, dynamic> data);

abstract class BaseStruct {
  Map<String, dynamic> toSerializableMap();
  String serialize() => json.encode(toSerializableMap());
}

List<T>? getStructList<T>(
  dynamic value,
  StructBuilder<T> structBuilder,
) =>
    value is! List
        ? null
        : value
            .whereType<Map<String, dynamic>>()
            .map((e) => structBuilder(e))
            .toList();
// Color? getSchemaColor(dynamic value) => value is String
//     ? fromCssColor(value)
//     : value is Color
//     ? value
//     : null;
//
// List<Color>? getColorsList(dynamic value) =>
//     value is! List ? null : value.map(getSchemaColor).withoutNulls;
List<T>? getDataList<T>(dynamic value) =>
    value is! List ? null : value.map((e) => castToType<T>(e)!).toList();
