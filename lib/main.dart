import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// Domain Model
class Exercise {
  final String id;
  final String name;
  final String description;
  final int duration; // in seconds
  final String difficulty;

  Exercise({
    required this.id,
    required this.name,
    required this.description,
    required this.duration,
    required this.difficulty,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      duration: int.parse(json['duration'].toString()),
      difficulty: json['difficulty'],
    );
  }
}

// Data Layer
abstract class ExerciseRepository {
  Future<List<Exercise>> fetchExercises();
  Future<void> markExerciseCompleted(String exerciseId);
  Future<List<String>> getCompletedExercises();
}

class ExerciseRepositoryImpl implements ExerciseRepository {
  final String apiUrl = 'https://68252ec20f0188d7e72c394f.mockapi.io/dev/workouts';
  final http.Client client;
  static const String _completedKey = 'completed_exercises';

  ExerciseRepositoryImpl({http.Client? client}) : client = client ?? http.Client();

  @override
  Future<List<Exercise>> fetchExercises() async {
    try {
      final response = await client.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Exercise.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load exercises: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  @override
  Future<void> markExerciseCompleted(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = await getCompletedExercises();
    if (!completed.contains(exerciseId)) {
      completed.add(exerciseId);
      await prefs.setStringList(_completedKey, completed);
    }
  }

  @override
  Future<List<String>> getCompletedExercises() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_completedKey) ?? [];
  }
}

// BLoC
abstract class ExerciseEvent {}

class FetchExercises extends ExerciseEvent {}

class MarkExerciseCompleted extends ExerciseEvent {
  final String exerciseId;
  MarkExerciseCompleted(this.exerciseId);
}

class ExerciseState {
  final List<Exercise> exercises;
  final List<String> completedExercises;
  final bool isLoading;
  final String? error;

  ExerciseState({
    this.exercises = const [],
    this.completedExercises = const [],
    this.isLoading = false,
    this.error,
  });

  ExerciseState copyWith({
    List<Exercise>? exercises,
    List<String>? completedExercises,
    bool? isLoading,
    String? error,
  }) {
    return ExerciseState(
      exercises: exercises ?? this.exercises,
      completedExercises: completedExercises ?? this.completedExercises,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ExerciseBloc extends Bloc<ExerciseEvent, ExerciseState> {
  final ExerciseRepository repository;

  ExerciseBloc(this.repository) : super(ExerciseState()) {
    on<FetchExercises>(_onFetchExercises);
    on<MarkExerciseCompleted>(_onMarkExerciseCompleted);
  }

  Future<void> _onFetchExercises(FetchExercises event, Emitter<ExerciseState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final exercises = await repository.fetchExercises();
      final completed = await repository.getCompletedExercises();
      emit(state.copyWith(
        exercises: exercises,
        completedExercises: completed,
        isLoading: false,
        error: null,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onMarkExerciseCompleted(MarkExerciseCompleted event, Emitter<ExerciseState> emit) async {
    await repository.markExerciseCompleted(event.exerciseId);
    final completed = await repository.getCompletedExercises();
    emit(state.copyWith(completedExercises: completed));
  }
}

// UI
void main() {
  runApp(const AletheaHealthApp());
}

class AletheaHealthApp extends StatelessWidget {
  const AletheaHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => ExerciseRepositoryImpl(),
      child: BlocProvider(
        create: (context) => ExerciseBloc(context.read<ExerciseRepositoryImpl>())
          ..add(FetchExercises()),
        child: MaterialApp(
          title: 'Alethea Health',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alethea Health'),
        centerTitle: true,
      ),
      body: BlocBuilder<ExerciseBloc, ExerciseState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${state.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<ExerciseBloc>().add(FetchExercises()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.exercises.length,
            itemBuilder: (context, index) {
              final exercise = state.exercises[index];
              final isCompleted = state.completedExercises.contains(exercise.id);
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(
                    exercise.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCompleted ? Colors.grey : Colors.black,
                    ),
                  ),
                  subtitle: Text('${exercise.duration} seconds'),
                  trailing: isCompleted
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExerciseDetailScreen(exercise: exercise),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ExerciseDetailScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({super.key, required this.exercise});

  @override
  _ExerciseDetailScreenState createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  int _secondsRemaining = 0;
  Timer? _timer;
  bool _isStarted = false;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.exercise.duration;
  }

  void _startTimer() {
    setState(() {
      _isStarted = true;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _timer?.cancel();
          _isCompleted = true;
          context.read<ExerciseBloc>().add(MarkExerciseCompleted(widget.exercise.id));
          _showCompletionDialog();
        }
      });
    });
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Exercise Completed!'),
        content: Text('You have completed ${widget.exercise.name}!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exercise.name),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Description: ${widget.exercise.description}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Duration: ${widget.exercise.duration} seconds',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Difficulty: ${widget.exercise.difficulty}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            if (_isStarted && !_isCompleted)
              Center(
                child: Text(
                  'Time Remaining: $_secondsRemaining seconds',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            const Spacer(),
            if (!_isStarted && !_isCompleted)
              Center(
                child: ElevatedButton(
                  onPressed: _startTimer,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: const Text('Start Exercise', style: TextStyle(fontSize: 18)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}