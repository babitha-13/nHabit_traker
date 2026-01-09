import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_model.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Screens/Authentication/authentication.dart';
import 'package:flutter/material.dart';
class AuthenticationPgModel extends FlutterFlowModel<SignIn> {
  ///  State fields for stateful widgets in this page.
  // State field(s) for TabBar widget.
  TabController? tabBarController;
  int get tabBarCurrentIndex =>
      tabBarController != null ? tabBarController!.index : 0;
  int get tabBarPreviousIndex =>
      tabBarController != null ? tabBarController!.previousIndex : 0;
  // State field(s) for emailAddress widget.
  FocusNode? emailAddressFocusNode;
  TextEditingController? emailAddressTextController;
  String? Function(BuildContext, String?)? emailAddressTextControllerValidator;
  // State field(s) for password widget.
  FocusNode? passwordFocusNode;
  TextEditingController? passwordTextController;
  late bool passwordVisibility;
  String? Function(BuildContext, String?)? passwordTextControllerValidator;
  // State field(s) for emailAddress_Create widget.
  FocusNode? emailAddressCreateFocusNode;
  TextEditingController? emailAddressCreateTextController;
  String? Function(BuildContext, String?)?
      emailAddressCreateTextControllerValidator;
  // State field(s) for password_Create widget.
  FocusNode? passwordCreateFocusNode;
  TextEditingController? passwordCreateTextController;
  late bool passwordCreateVisibility;
  String? Function(BuildContext, String?)?
      passwordCreateTextControllerValidator;
  // State field(s) for passwordConfirm widget.
  FocusNode? passwordConfirmFocusNode;
  TextEditingController? passwordConfirmTextController;
  late bool passwordConfirmVisibility;
  String? Function(BuildContext, String?)?
      passwordConfirmTextControllerValidator;
  @override
  void initState(BuildContext context) {
    passwordVisibility = false;
    passwordCreateVisibility = false;
    passwordConfirmVisibility = false;
    // Initialize validators
    emailAddressTextControllerValidator = _emailValidator;
    passwordTextControllerValidator = _passwordValidator;
    emailAddressCreateTextControllerValidator = _emailValidator;
    passwordCreateTextControllerValidator = _passwordStrengthValidator;
    passwordConfirmTextControllerValidator = _passwordConfirmValidator;
  }
  // Email validation function
  String? _emailValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Email is required';
    }
    // Use the existing email regex from flutter_flow_util.dart
    final emailRegex = RegExp(kTextValidatorEmailRegex);
    if (!emailRegex.hasMatch(val)) {
      return 'Please enter a valid email address';
    }
    return null;
  }
  // Password validation for sign-in (basic)
  String? _passwordValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Password is required';
    }
    if (val.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }
  // Password validation for sign-up (simplified - no strength requirements)
  String? _passwordStrengthValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Password is required';
    }
    if (val.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }
  // Password confirmation validation
  String? _passwordConfirmValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Please confirm your password';
    }
    // Check if passwords match
    if (passwordCreateTextController?.text != val) {
      return 'Passwords do not match';
    }
    return null;
  }
  @override
  void dispose() {
    tabBarController?.dispose();
    emailAddressFocusNode?.dispose();
    emailAddressTextController?.dispose();
    passwordFocusNode?.dispose();
    passwordTextController?.dispose();
    emailAddressCreateFocusNode?.dispose();
    emailAddressCreateTextController?.dispose();
    passwordCreateFocusNode?.dispose();
    passwordCreateTextController?.dispose();
    passwordConfirmFocusNode?.dispose();
    passwordConfirmTextController?.dispose();
  }
}
