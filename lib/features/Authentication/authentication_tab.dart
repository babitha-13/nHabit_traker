import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/firebase_auth_manager.dart';
import 'package:habit_tracker/services/flutter_flow_animations.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/features/Authentication/authentication_pg_model.dart';
import 'package:habit_tracker/features/Authentication/sign_in_card.dart';
import 'package:habit_tracker/features/Authentication/sign_up_card.dart';

class AuthenticationTab extends StatelessWidget {
  final AuthenticationPgModel model;
  final FirebaseAuthManager authManager;
  final Map<String, AnimationInfo> animationsMap;
  AuthenticationTab(
      {super.key,
      required this.model,
      required this.authManager,
      required this.animationsMap});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            flex: 8,
            child: Container(
              width: 100.0,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: (FlutterFlowTheme.of(context) is LightModeTheme)
                    ? (FlutterFlowTheme.of(context) as LightModeTheme)
                        .neumorphicRadialGradient
                    : RadialGradient(
                        colors: [
                          FlutterFlowTheme.of(context).primaryBackground,
                          FlutterFlowTheme.of(context).secondaryBackground,
                        ],
                        center: Alignment.center,
                        radius: 8,
                      ),
              ),
              alignment: const AlignmentDirectional(0.0, -1.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        0.0,
                        44.0,
                        0.0,
                        0.0,
                      ),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 602.0),
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(16.0),
                            bottomRight: Radius.circular(16.0),
                            topLeft: Radius.circular(0.0),
                            topRight: Radius.circular(0.0),
                          ),
                        ),
                        alignment: const AlignmentDirectional(-1.0, 0.0),
                        child: Align(
                          alignment: const AlignmentDirectional(-1.0, 0.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  16.0,
                                  0.0,
                                  0.0,
                                  0.0,
                                ),
                                child: Text(
                                  'Habit Tracker',
                                  style: FlutterFlowTheme.of(context)
                                      .headlineMedium
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight: FlutterFlowTheme.of(
                                            context,
                                          ).headlineMedium.fontWeight,
                                          fontStyle: FlutterFlowTheme.of(
                                            context,
                                          ).headlineMedium.fontStyle,
                                        ),
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(
                                          context,
                                        ).headlineMedium.fontWeight,
                                        fontStyle: FlutterFlowTheme.of(
                                          context,
                                        ).headlineMedium.fontStyle,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      height: 700.0,
                      constraints: const BoxConstraints(maxWidth: 602.0),
                      decoration: const BoxDecoration(),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16.0,
                          0.0,
                          16.0,
                          0.0,
                        ),
                        child: Column(
                          children: [
                            Align(
                              alignment: const Alignment(-1.0, 0),
                              child: TabBar(
                                isScrollable: true,
                                labelColor: FlutterFlowTheme.of(
                                  context,
                                ).primaryText,
                                unselectedLabelColor: FlutterFlowTheme.of(
                                  context,
                                ).accent4,
                                labelPadding: const EdgeInsets.all(16.0),
                                labelStyle: FlutterFlowTheme.of(context)
                                    .displaySmall
                                    .override(
                                      font: GoogleFonts.interTight(
                                        fontWeight: FlutterFlowTheme.of(
                                          context,
                                        ).displaySmall.fontWeight,
                                        fontStyle: FlutterFlowTheme.of(
                                          context,
                                        ).displaySmall.fontStyle,
                                      ),
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(
                                        context,
                                      ).displaySmall.fontWeight,
                                      fontStyle: FlutterFlowTheme.of(
                                        context,
                                      ).displaySmall.fontStyle,
                                    ),
                                unselectedLabelStyle: FlutterFlowTheme.of(
                                  context,
                                ).displaySmall.override(
                                      font: GoogleFonts.interTight(
                                        fontWeight: FontWeight.normal,
                                        fontStyle: FlutterFlowTheme.of(
                                          context,
                                        ).displaySmall.fontStyle,
                                      ),
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(
                                        context,
                                      ).displaySmall.fontStyle,
                                    ),
                                indicatorColor: FlutterFlowTheme.of(
                                  context,
                                ).primary,
                                indicatorWeight: 4.0,
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0,
                                  12.0,
                                  16.0,
                                  12.0,
                                ),
                                tabs: const [
                                  Tab(text: 'Log In'),
                                  Tab(text: 'Create Account'),
                                ],
                                controller: model.tabBarController,
                                onTap: (i) async {
                                  [() async {}, () async {}][i]();
                                },
                              ),
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: model.tabBarController,
                                children: [
                                  SignInCard(
                                      model: model,
                                      authManager: authManager,
                                      animationsMap: animationsMap),
                                  SignUpCard(
                                      model: model,
                                      authManager: authManager,
                                      animationsMap: animationsMap)
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (responsiveVisibility(
            context: context,
            phone: false,
            tablet: false,
          ))
            Expanded(
              flex: 6,
              child: Container(
                width: 100.0,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).secondaryBackground,
                  image: const DecorationImage(
                    fit: BoxFit.cover,
                    image: CachedNetworkImageProvider(
                      'https://images.unsplash.com/photo-1508385082359-f38ae991e8f2?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1374&q=80',
                    ),
                  ),
                  borderRadius: BorderRadius.circular(0.0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
