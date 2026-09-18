import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/onboarding_controller.dart';
import 'welcome_step.dart';
import 'language_selection_step.dart';
import 'artist_selection_step.dart';

/// Root widget for the first-launch onboarding flow.
///
/// Designed to match Sonara's aesthetic with a custom header, step indicators,
/// back navigation, and smooth animated transitions.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, this.onComplete});

  /// Called when the entire flow finishes (used by login-later to dismiss).
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<OnboardingController>();
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.secondary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Obx(() {
          final step = controller.currentStep.value;

          // If complete, call onComplete callback (login-later flow)
          if (step == OnboardingStep.complete && onComplete != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onComplete!();
            });
          }

          final int stepIndex = _getStepIndex(step);

          return Column(
            children: [
              // Top Navigation Bar matching Sonara's header style
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Back button
                    if (controller.canGoBack)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        tooltip: "Back",
                        onPressed: () => controller.goToPreviousStep(),
                      )
                    else
                      const SizedBox(width: 48, height: 48),

                    // Centered Stepper Indicator
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (index) {
                            final isActive = index <= stepIndex;
                            final isCurrent = index == stepIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 6,
                              width: isCurrent ? 28 : 14,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: isActive
                                    ? primaryColor
                                    : theme.dividerColor.withValues(alpha: 0.2),
                                boxShadow: isCurrent
                                    ? [
                                        BoxShadow(
                                          color: primaryColor.withValues(alpha: 0.4),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                            );
                          }),
                        ),
                      ),
                    ),

                    // Skip button
                    TextButton(
                      onPressed: () => controller.skipAll(),
                      child: Text(
                        "Skip",
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Step Content Area
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _buildStep(step),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  int _getStepIndex(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
      case OnboardingStep.loginOrSkip:
        return 0;
      case OnboardingStep.musicLanguageSelection:
        return 1;
      case OnboardingStep.artistSelection:
      case OnboardingStep.complete:
        return 2;
    }
  }

  Widget _buildStep(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
      case OnboardingStep.loginOrSkip:
        return const WelcomeStep(key: ValueKey('welcome'));
      case OnboardingStep.musicLanguageSelection:
        return const LanguageSelectionStep(key: ValueKey('language'));
      case OnboardingStep.artistSelection:
        return ArtistSelectionStep(
          key: const ValueKey('artist'),
          onComplete: onComplete,
        );
      case OnboardingStep.complete:
        return const SizedBox.shrink(key: ValueKey('complete'));
    }
  }
}
