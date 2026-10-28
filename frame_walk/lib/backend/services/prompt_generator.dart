// Creates a class to manage photography prompts.
class PromptGenerator {

  // Stores a list of photography prompts for each location.
  final Map<String, List<String>> prompts;

  // Constructor: receives the prompts when the object is created.
  PromptGenerator(this.prompts);

  // Gets the photography prompts for a selected location.
  List<String> getPrompts(String stopId) {

    // Checks whether the location ID is empty.
    if (stopId.isEmpty) {

      // Shows an error if no location ID was provided.
      throw ArgumentError('Stop ID cannot be empty');
    }

    // Returns prompts for the location.
    // If the location doesn't exist, returns an empty list.
    return prompts[stopId] ?? [];
  }
}
