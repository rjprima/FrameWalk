// Imports Flutter's testing framework.
import 'package:flutter_test/flutter_test.dart';

// Imports the PromptGenerator class we created.
import '../services/prompt_generator.dart';

// Main function where all tests begin.
void main() {

  // Groups all PromptGenerator tests together.
  group('PromptGenerator Tests', () {

    // Creates a PromptGenerator with example locations.
    final generator = PromptGenerator({

      // The park location has two photography prompts.
      'park': [
        'Photograph an interesting shadow',
        'Find a repeating pattern',
      ],

      // The library location has no photography prompts.
      'library': [],
    });

    // TEST 1: Checks if a valid location returns prompts.
    test('Returns prompts for a valid stop', () {

      // Gets prompts for the park and checks that there are 2.
      expect(generator.getPrompts('park'), hasLength(2));
    });

    // TEST 2: Checks what happens when a location does not exist.
    test('Returns empty list for unknown stop', () {

      // An unknown location should return an empty list.
      expect(generator.getPrompts('unknown'), isEmpty);
    });

    // TEST 3: Checks if an empty location ID is rejected.
    test('Rejects an empty stop ID', () {

      // An empty location ID should throw an ArgumentError.
      expect(
        () => generator.getPrompts(''),
        throwsArgumentError,
      );
    });
  });
}
