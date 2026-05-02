# NoteLetter Flutter Frontend — CLAUDE.md

## Overview
This folder contains the Flutter mobile application for NoteLetter, providing a native cross-platform interface for document upload, search, and newsletter management.

## Tech Stack
- **Framework**: Flutter 3.x
- **State Management**: Provider/Riverpod (check current implementation)
- **Navigation**: Flutter Navigator 2.0
- **HTTP**: Dio or http package
- **Authentication**: Firebase Auth Flutter SDK
- **Local Storage**: SharedPreferences/Hive for caching

## Project Structure

```
Flutter Frontend/
├── CLAUDE.md                        ← you are here
├── README.md                        ← project setup instructions
├── pubspec.yaml                     ← dependencies and configuration
├── analysis_options.yaml            ← linting rules
├── android/                         ← Android-specific configuration
├── ios/                             ← iOS-specific configuration
├── web/                             ← Web platform configuration
├── lib/
│   ├── main.dart                    ← app entry point
│   ├── app.dart                     ← app widget and theme setup
│   ├── core/                        ← core utilities and constants
│   │   ├── constants/               ← API endpoints, app constants
│   │   ├── services/                ← API clients, auth service
│   │   ├── utils/                   ← helpers, formatters
│   │   └── widgets/                 ← reusable base widgets
│   ├── features/                    ← feature-based organization
│   │   ├── auth/                    ← authentication screens/logic
│   │   ├── upload/                  ← document upload flow
│   │   ├── search/                  ← note search functionality
│   │   ├── library/                 ← document library view
│   │   └── newsletter/              ← newsletter settings/history
│   └── shared/                      ← shared components
│       ├── models/                  ← data models
│       ├── widgets/                 ← common UI components
│       └── themes/                  ├── app theming
└── test/                           ← unit and widget tests
```

## Key Features

### Document Upload
- **Multi-format support**: PDF, Word, images, web URLs, YouTube links
- **Direct upload**: Get signed URLs from backend → upload directly to Cloud Storage
- **Multi-image handling**: Batch upload for image sets
- **Progress tracking**: Real-time upload progress and processing status

### Search & Discovery
- **Vector search**: Semantic search over all uploaded content
- **Context viewing**: View matched chunks with surrounding context
- **Document linking**: Jump from search results to full documents
- **Filtering**: By document type, date, or source

### Newsletter Management
- **Settings**: Configure newsletter frequency, purpose, and delivery
- **History**: View past newsletters and their content
- **Purpose framing**: Free-text goal that influences content selection

## API Integration

### Authentication
```dart
// Firebase Auth integration
class AuthService {
  Future<UserCredential> signInWithEmail(String email, String password);
  Future<UserCredential> signUpWithEmail(String email, String password);
  Future<void> signOut();
  Stream<User?> authStateChanges();
}
```

### Document Upload
```dart
// Upload session creation
class UploadService {
  Future<UploadSession> createUploadSession(String filename);
  Future<UploadSession> createMultiImageSession(List<String> filenames);
  Future<void> signalUploadsComplete(String sessionId);
  Future<void> uploadFile(File file, String signedUrl);
}
```

### Search
```dart
// Vector search integration
class SearchService {
  Future<List<SearchResult>> searchNotes(String query, {int limit = 10});
  Future<ChunkContext> getChunkContext(String chunkId);
  Future<Document> getDocument(String documentId);
}
```

## State Management Pattern

### Provider-based structure (if using Provider)
```dart
// Example providers
class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  
  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  
  Future<void> signIn(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _user = await _authService.signInWithEmail(email, password);
    } catch (e) {
      // Handle error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

## UI Components

### Common Widgets
- **LoadingIndicator**: Consistent loading states
- **ErrorWidget**: Error display with retry options
- **DocumentCard**: Document preview with metadata
- **SearchResult**: Search result with context preview
- **UploadProgress**: Upload progress bar with status

### Screen Structure
- **AppBar**: Consistent navigation and actions
- **BottomNavigation**: Main app navigation
- **FloatingActionButton**: Quick actions (upload, search)
- **Drawer**: Additional navigation and user profile

## Firebase Integration

### Authentication Setup
```dart
// Firebase Auth initialization
await Firebase.initializeApp();
FirebaseAuth auth = FirebaseAuth.instance;
```

### Cloud Functions Calls
```dart
// HTTP callable functions
HttpsCallableResult result = await FirebaseFunctions.instance
    .httpsCallable('fn_search_notes')
    .call({'query': searchTerm, 'limit': 10});
```

## Development Guidelines

### Code Organization
- **Feature-first**: Organize by feature, not by file type
- **Separation of concerns**: UI, business logic, and data layers separate
- **Dependency injection**: Use get_it or similar for service injection

### Testing Strategy
- **Unit tests**: Business logic and utilities
- **Widget tests**: UI component behavior
- **Integration tests**: Complete user flows

### Performance Considerations
- **Lazy loading**: Load documents and chunks on demand
- **Image optimization**: Compress and cache images appropriately
- **Network optimization**: Implement proper caching strategies

## Environment Configuration

### Development
```yaml
# .env development
FIREBASE_PROJECT_ID=luxletter-b7a40-dev
API_BASE_URL=https://us-central1-luxletter-b7a40-dev.cloudfunctions.net
```

### Production
```yaml
# .env production
FIREBASE_PROJECT_ID=luxletter-b7a40
API_BASE_URL=https://us-central1-luxletter-b7a40.cloudfunctions.net
```

## Deployment

### Android
```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

### iOS
```bash
# Build iOS app
flutter build ios --release
```

### Web
```bash
# Build web app
flutter build web --release
```

## Key Dependencies

Check `pubspec.yaml` for current dependencies, but typically include:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: latest
  firebase_auth: latest
  cloud_firestore: latest
  provider: latest
  dio: latest
  shared_preferences: latest
  image_picker: latest
  file_picker: latest
  url_launcher: latest
```

## Common Issues & Solutions

### Firebase Initialization
- Ensure `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) are properly configured
- Check Firebase project ID matches environment

### File Upload
- Handle large files with proper progress indicators
- Implement retry logic for failed uploads
- Validate file types before upload

### Search Performance
- Implement debouncing for search queries
- Cache search results when appropriate
- Handle pagination for large result sets
