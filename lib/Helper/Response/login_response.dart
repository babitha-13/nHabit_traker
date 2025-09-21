import 'dart:convert';

class LoginResponse {
   String? email;
   String? password;
   String? uid;

  LoginResponse({
     this.email,
    this.password,
    this.uid,
  });

  Map<String, dynamic> toJson() => {
    "email": email,
    "password": password,
    "uid": uid,
  };

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      email: json["email"] ?? '',
      password: json["password"] ?? '',
      uid: json["uid"]??''
    );
  }

  static LoginResponse? fromRawJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      final decoded = json.decode(jsonString);
      return LoginResponse.fromJson(decoded);
    } catch (e) {
      return null;
    }
  }

  String toRawJson() => json.encode(toJson());
}
