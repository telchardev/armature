import 'package:flutter/material.dart';

import '../widgets/landing/features_section.dart';
import '../widgets/landing/footer_cta_section.dart';
import '../widgets/landing/hero_section.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        children: [HeroSection(), FeaturesSection(), FooterCtaSection()],
      ),
    );
  }
}
