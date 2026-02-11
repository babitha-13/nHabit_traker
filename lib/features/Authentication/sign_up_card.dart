import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_animations.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_widgets.dart';
import 'package:habit_tracker/Helper/Helpers/constants.dart';
import 'package:habit_tracker/Screens/Authentication/authentication_pg_model.dart';
import 'package:habit_tracker/main.dart';

class SignUpCard extends StatefulWidget {
  final AuthenticationPgModel model;
  final FirebaseAuthManager authManager;
  final Map<String, AnimationInfo> animationsMap;
  const SignUpCard(
      {super.key,
      required this.model,
      required this.authManager,
      required this.animationsMap});
  @override
  State<SignUpCard> createState() => _SignUpCardState();
}

class _SignUpCardState extends State<SignUpCard> {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const AlignmentDirectional(
        0.0,
        0.0,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          12.0,
          0.0,
          12.0,
          12.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                0.0,
                12.0,
                0.0,
                24.0,
              ),
              child: Text(
                'Are you on the app for the first time? Enter an email ID and password to create your account.',
                style: FlutterFlowTheme.of(
                  context,
                ).labelMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight: FlutterFlowTheme.of(
                          context,
                        ).labelMedium.fontWeight,
                        fontStyle: FlutterFlowTheme.of(
                          context,
                        ).labelMedium.fontStyle,
                        color: FlutterFlowTheme.of(
                          context,
                        ).accent4,
                      ),
                      color: FlutterFlowTheme.of(
                        context,
                      ).accent4,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                0.0,
                0.0,
                0.0,
                16.0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextFormField(
                  controller: widget.model.emailAddressCreateTextController,
                  focusNode: widget.model.emailAddressCreateFocusNode,
                  autofocus: true,
                  autofillHints: const [
                    AutofillHints.email,
                  ],
                  obscureText: false,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: FlutterFlowTheme.of(
                      context,
                    ).labelMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontWeight,
                            fontStyle: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontStyle,
                            color: FlutterFlowTheme.of(
                              context,
                            ).accent4,
                          ),
                          color: FlutterFlowTheme.of(
                            context,
                          ).accent4,
                        ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).primaryBackground,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).primary,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).error,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).error,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    filled: true,
                    fillColor: FlutterFlowTheme.of(
                      context,
                    ).secondaryBackground,
                    contentPadding: const EdgeInsets.all(
                      24.0,
                    ),
                  ),
                  style: FlutterFlowTheme.of(
                    context,
                  ).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight: FlutterFlowTheme.of(
                            context,
                          ).bodyMedium.fontWeight,
                          fontStyle: FlutterFlowTheme.of(
                            context,
                          ).bodyMedium.fontStyle,
                          color: FlutterFlowTheme.of(
                            context,
                          ).primaryText,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FlutterFlowTheme.of(
                          context,
                        ).bodyMedium.fontWeight,
                        fontStyle: FlutterFlowTheme.of(
                          context,
                        ).bodyMedium.fontStyle,
                        color: FlutterFlowTheme.of(
                          context,
                        ).primaryText,
                      ),
                  keyboardType: TextInputType.emailAddress,
                  cursorColor: FlutterFlowTheme.of(
                    context,
                  ).primary,
                  validator: widget
                      .model.emailAddressCreateTextControllerValidator
                      ?.asValidator(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                0.0,
                0.0,
                0.0,
                16.0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextFormField(
                  controller: widget.model.passwordCreateTextController,
                  focusNode: widget.model.passwordCreateFocusNode,
                  autofocus: false,
                  autofillHints: const [
                    AutofillHints.password,
                  ],
                  obscureText: !widget.model.passwordCreateVisibility,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: FlutterFlowTheme.of(
                      context,
                    ).labelMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontWeight,
                            fontStyle: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontStyle,
                            color: FlutterFlowTheme.of(
                              context,
                            ).accent4,
                          ),
                          color: FlutterFlowTheme.of(
                            context,
                          ).accent4,
                        ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).primaryBackground,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).primary,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).error,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).error,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    filled: true,
                    fillColor: FlutterFlowTheme.of(
                      context,
                    ).secondaryBackground,
                    contentPadding: const EdgeInsets.all(
                      24.0,
                    ),
                    suffixIcon: InkWell(
                      onTap: () {
                        if (mounted) {
                          setState(() {
                            widget.model.passwordCreateVisibility =
                                !widget.model.passwordCreateVisibility;
                          });
                        }
                      },
                      focusNode: FocusNode(
                        skipTraversal: true,
                      ),
                      child: Icon(
                        widget.model.passwordCreateVisibility
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: FlutterFlowTheme.of(
                          context,
                        ).accent4,
                        size: 24.0,
                      ),
                    ),
                  ),
                  style: FlutterFlowTheme.of(
                    context,
                  ).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight: FlutterFlowTheme.of(
                            context,
                          ).bodyMedium.fontWeight,
                          fontStyle: FlutterFlowTheme.of(
                            context,
                          ).bodyMedium.fontStyle,
                          color: FlutterFlowTheme.of(context).primaryText,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FlutterFlowTheme.of(
                          context,
                        ).bodyMedium.fontWeight,
                        fontStyle: FlutterFlowTheme.of(
                          context,
                        ).bodyMedium.fontStyle,
                        color: FlutterFlowTheme.of(context).primaryText,
                      ),
                  cursorColor: FlutterFlowTheme.of(
                    context,
                  ).primary,
                  validator: widget.model.passwordCreateTextControllerValidator
                      .asValidator(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                0.0,
                0.0,
                0.0,
                16.0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextFormField(
                  controller: widget.model.passwordConfirmTextController,
                  focusNode: widget.model.passwordConfirmFocusNode,
                  autofocus: false,
                  autofillHints: const [
                    AutofillHints.password,
                  ],
                  obscureText: !widget.model.passwordConfirmVisibility,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    labelStyle: FlutterFlowTheme.of(
                      context,
                    ).labelMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontWeight,
                            fontStyle: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontStyle,
                            color: FlutterFlowTheme.of(
                              context,
                            ).accent4,
                          ),
                          color: FlutterFlowTheme.of(
                            context,
                          ).accent4,
                        ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).primaryBackground,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).primary,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).error,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: FlutterFlowTheme.of(
                          context,
                        ).error,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(
                        40.0,
                      ),
                    ),
                    filled: true,
                    fillColor: FlutterFlowTheme.of(
                      context,
                    ).secondaryBackground,
                    contentPadding: const EdgeInsets.all(
                      24.0,
                    ),
                    suffixIcon: InkWell(
                      onTap: () {
                        if (mounted) {
                          setState(() {
                            widget.model.passwordConfirmVisibility =
                                !widget.model.passwordConfirmVisibility;
                          });
                        }
                      },
                      focusNode: FocusNode(
                        skipTraversal: true,
                      ),
                      child: Icon(
                        widget.model.passwordConfirmVisibility
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: FlutterFlowTheme.of(
                          context,
                        ).accent4,
                        size: 24.0,
                      ),
                    ),
                  ),
                  style: FlutterFlowTheme.of(
                    context,
                  ).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight: FlutterFlowTheme.of(
                            context,
                          ).bodyMedium.fontWeight,
                          fontStyle: FlutterFlowTheme.of(
                            context,
                          ).bodyMedium.fontStyle,
                          color: FlutterFlowTheme.of(
                            context,
                          ).primaryText,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FlutterFlowTheme.of(
                          context,
                        ).bodyMedium.fontWeight,
                        fontStyle: FlutterFlowTheme.of(
                          context,
                        ).bodyMedium.fontStyle,
                        color: FlutterFlowTheme.of(
                          context,
                        ).primaryText,
                      ),
                  minLines: 1,
                  cursorColor: FlutterFlowTheme.of(
                    context,
                  ).primary,
                  validator: widget.model.passwordConfirmTextControllerValidator
                      ?.asValidator(context),
                ),
              ),
            ),
            Align(
              alignment: const AlignmentDirectional(
                0.0,
                0.0,
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  0.0,
                  0.0,
                  0.0,
                  16.0,
                ),
                child: FFButtonWidget(
                  onPressed: () async {
                    final email =
                        widget.model.emailAddressTextController.text.trim();
                    final password =
                        widget.model.passwordTextController.text.trim();
                    if (!_isSignUpFormValid()) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please fix the validation errors above.',
                          ),
                        ),
                      );
                      return;
                    }
                    final user = await authManager.createAccountWithEmail(
                      context,
                      widget.model.emailAddressCreateTextController.text,
                      widget.model.passwordCreateTextController.text,
                    );
                    if (user == null) {
                      return;
                    }
                    users.uid = user.uid;
                    users.email = email;
                    users.password = password;
                    final jsonString = users.toRawJson();
                    await sharedPref.saveValue("Auth", jsonString);
                    await sharedPref.saveAuthData(users);
                    Navigator.pushReplacementNamed(context, home);
                  },
                  text: 'Create Account',
                  options: FFButtonOptions(
                    width: 230.0,
                    height: 52.0,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      0.0,
                      0.0,
                      0.0,
                      0.0,
                    ),
                    iconPadding: const EdgeInsetsDirectional.fromSTEB(
                      0.0,
                      0.0,
                      0.0,
                      0.0,
                    ),
                    color: FlutterFlowTheme.of(
                      context,
                    ).primary,
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Inter Tight',
                      fontSize: 18.0,
                    ),
                    borderSide: const BorderSide(
                      color: Colors.transparent,
                      width: 1.0,
                    ),
                    borderRadius: BorderRadius.circular(
                      40.0,
                    ),
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Align(
                  alignment: const AlignmentDirectional(
                    0.0,
                    0.0,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16.0,
                      0.0,
                      16.0,
                      24.0,
                    ),
                    child: Text(
                      'Or continue with',
                      textAlign: TextAlign.center,
                      style: FlutterFlowTheme.of(context).labelMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FlutterFlowTheme.of(
                                context,
                              ).labelMedium.fontWeight,
                              fontStyle: FlutterFlowTheme.of(
                                context,
                              ).labelMedium.fontStyle,
                              color: FlutterFlowTheme.of(
                                context,
                              ).accent4,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontWeight,
                            fontStyle: FlutterFlowTheme.of(
                              context,
                            ).labelMedium.fontStyle,
                            color: FlutterFlowTheme.of(
                              context,
                            ).accent4,
                          ),
                    ),
                  ),
                ),
                Align(
                  alignment: const AlignmentDirectional(
                    0.0,
                    0.0,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      0.0,
                      0.0,
                      0.0,
                      16.0,
                    ),
                    child: Wrap(
                      spacing: 16.0,
                      runSpacing: 0.0,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      direction: Axis.horizontal,
                      runAlignment: WrapAlignment.center,
                      verticalDirection: VerticalDirection.down,
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            0.0,
                            0.0,
                            0.0,
                            16.0,
                          ),
                          child: FFButtonWidget(
                            onPressed: () async {
                              // GoRouter.of(context).prepareAuthEvent();
                              // final user = await widget.authManager.signInWithGoogle(context);
                              // if (user == null) return;
                              // await _saveUserToDB(user, provider: "google");
                              // Navigator.pushReplacementNamed(context, home);
                            },
                            text: 'Continue with Google',
                            icon: const FaIcon(
                              FontAwesomeIcons.google,
                              size: 20.0,
                            ),
                            options: FFButtonOptions(
                              width: 230.0,
                              height: 44.0,
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0,
                                0.0,
                                0.0,
                                0.0,
                              ),
                              iconPadding: const EdgeInsetsDirectional.fromSTEB(
                                0.0,
                                0.0,
                                0.0,
                                0.0,
                              ),
                              color: FlutterFlowTheme.of(
                                context,
                              ).secondaryBackground,
                              textStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontStyle: FlutterFlowTheme.of(
                                        context,
                                      ).bodyMedium.fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FlutterFlowTheme.of(
                                      context,
                                    ).bodyMedium.fontStyle,
                                  ),
                              elevation: 0.0,
                              borderSide: BorderSide(
                                color: FlutterFlowTheme.of(
                                  context,
                                ).primary,
                                width: 2.0,
                              ),
                              borderRadius: BorderRadius.circular(
                                40.0,
                              ),
                              hoverColor: FlutterFlowTheme.of(
                                context,
                              ).primaryBackground,
                            ),
                          ),
                        ),
                        isAndroid
                            ? Container()
                            : Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0,
                                  0.0,
                                  0.0,
                                  16.0,
                                ),
                                child: FFButtonWidget(
                                  onPressed: () async {
                                    // GoRouter.of(context).prepareAuthEvent();
                                    // final user = await widget.authManager.signInWithApple(context);
                                    // if (user == null) return;
                                    // await _saveUserToDB(user, provider: "apple");
                                    // Navigator.pushReplacementNamed(context, home);
                                  },
                                  text: 'Continue with Apple',
                                  icon: const FaIcon(
                                    FontAwesomeIcons.apple,
                                    size: 20.0,
                                  ),
                                  options: FFButtonOptions(
                                    width: 230.0,
                                    height: 44.0,
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                      0.0,
                                      0.0,
                                      0.0,
                                      0.0,
                                    ),
                                    iconPadding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                      0.0,
                                      0.0,
                                      0.0,
                                      0.0,
                                    ),
                                    color: FlutterFlowTheme.of(
                                      context,
                                    ).secondaryBackground,
                                    textStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight: FontWeight.bold,
                                            fontStyle: FlutterFlowTheme.of(
                                              context,
                                            ).bodyMedium.fontStyle,
                                            color: FlutterFlowTheme.of(
                                              context,
                                            ).primaryText,
                                          ),
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.bold,
                                          fontStyle: FlutterFlowTheme.of(
                                            context,
                                          ).bodyMedium.fontStyle,
                                        ),
                                    elevation: 2.0,
                                    borderSide: const BorderSide(
                                      color: Colors.transparent,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      40.0,
                                    ),
                                    hoverColor: FlutterFlowTheme.of(
                                      context,
                                    ).primaryBackground,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ).animateOnPageLoad(
            widget.animationsMap['columnOnPageLoadAnimation2']!),
      ),
    );
  }

  bool _isSignUpFormValid() {
    final emailError =
        widget.model.emailAddressCreateTextControllerValidator?.call(
      context,
      widget.model.emailAddressCreateTextController?.text,
    );
    final passwordError =
        widget.model.passwordCreateTextControllerValidator?.call(
      context,
      widget.model.passwordCreateTextController?.text,
    );
    final confirmPasswordError =
        widget.model.passwordConfirmTextControllerValidator?.call(
      context,
      widget.model.passwordConfirmTextController?.text,
    );
    return emailError == null &&
        passwordError == null &&
        confirmPasswordError == null;
  }
}
