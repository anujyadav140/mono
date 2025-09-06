# Mono Moments
**Target Platforms:** Android

**Tech Stack:** [Flutter](https://flutter.dev/) (frontend), [Firebase AI Logic](https://firebase.google.com/docs/ai-logic) (Gemini API in Vertex AI for the backend), Provider, Google Maps Platform (Places, Maps SDK, Routes, Photos)

![Agentic App Manager – Firebase AI Model Constructors w/ Screenshots](README/AppScreenshots.png)

This app demonstrates how to build an agentic, in‑trip companion for Expedia using Firebase AI Logic with the Gemini API in Vertex AI. The agent continuously watches micro‑moments ("Where should I eat now?", "My flight is delayed—what can I do?", "It’s raining—what indoor activity fits 2 hours?") and proactively suggests the next best action using live context from Maps data, itinerary details, weather, and user preferences.

> [!NOTE]
> Check out this Google I/O 2025 talk for a full walkthrough: [How to build agentic apps with Flutter and Firebase AI Logic](https://www.youtube.com/watch?v=xo271p-Fl_4).

## Getting Started

1. Follow [these instructions](https://firebase.google.com/docs/ai-logic/get-started?&api=vertex#set-up-firebase) 
to set up a Firebase project & connect the app to Firebase using `flutterfire configure`

1. Run `flutter pub get` in the root of the project directory `mono_moments` to
install the Flutter app dependencies

1. Run `flutter run` to start the app on Android

Check out [this table](https://firebase.google.com/docs/ai-logic/models) for more on the various supported models & features.

## Architecture

### `GenerativeModel`
See code in [`lib/agentic_app_manager/`](https://github.com/flutter/demos/blob/main/agentic_app_manager/lib/agentic_app_manager/)
![GenerativeModel Architecture Diagram](README/AgenticAppManagerArchitectureDiagram.png)

### `ImagenModel`
See code in [`lib/image_generator.dart`](https://github.com/flutter/demos/blob/main/agentic_app_manager/lib/image_generator.dart)
![ImagenModel Architecture Diagram](README/ImagenArchitectureDiagram.png)

### `LiveGenerativeModel`
See code in [`lib/audio_app_manager/audio_app_manager_demo.dart`](https://github.com/flutter/demos/blob/main/agentic_app_manager/lib/audio_app_manager/audio_app_manager_demo.dart)
![ImagenModel Architecture Diagram](README/AgenticAppManagerAudioArchitectureDiagram.png)

## Resources
- [[Codelab] Build a Gemini powered Flutter app with Flutter & Firebase AI Logic](https://codelabs.developers.google.com/codelabs/flutter-gemini-colorist)
- [Demo App] [Colorist](https://github.com/flutter/demos/tree/main/vertex_ai_firebase_flutter_app): A Flutter application that explores LLM tooling interfaces by allowing users to describe colors in natural language. The app uses Gemini LLM to interpret descriptions and change the color of a displayed square by calling specialized color tools.
- [Firebase AI Logic docs](https://firebase.google.com/docs/ai-logic)

