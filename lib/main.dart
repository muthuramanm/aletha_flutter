import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

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
      id: json['id'] ?? '',
      name: json['description'] ?? 'Unknown Exercise',
      description: json['description'] ?? 'No description',
      duration: int.tryParse(json['duration'].toString()) ?? 0,
      difficulty: json['difficulty'] ?? 'Unknown',
    );
  }
}

// Data Layer
abstract class ExerciseRepository {
  Future<List<Exercise>> fetchExercises();
  Future<void> markExerciseCompleted(String exerciseId, DateTime date);
  Future<List<String>> getCompletedExercises();
  Future<Map<DateTime, int>> getCompletionHistory();
  Future<int> getStreak();
}

class ExerciseRepositoryImpl implements ExerciseRepository {
  final String apiUrl = 'https://68252ec20f0188d7e72c394f.mockapi.io/dev/workouts';
  final http.Client client;
  static const String _completedKey = 'completed_exercises';
  static const String _historyKey = 'completion_history';
  static const String _streakKey = 'streak';

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
  Future<void> markExerciseCompleted(String exerciseId, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = await getCompletedExercises();
    if (!completed.contains(exerciseId)) {
      completed.add(exerciseId);
      await prefs.setStringList(_completedKey, completed);
    }
    final history = await getCompletionHistory();
    final dateKey = DateTime(date.year, date.month, date.day);
    history[dateKey] = (history[dateKey] ?? 0) + 1;
    await prefs.setString(
      _historyKey,
      json.encode(
        history.map((key, value) => MapEntry(
              key.toIso8601String(),
              value,
            )),
      ),
    );
    final streak = await _calculateStreak();
    await prefs.setInt(_streakKey, streak);
  }

  @override
  Future<List<String>> getCompletedExercises() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_completedKey) ?? [];
  }

  @override
  Future<Map<DateTime, int>> getCompletionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_historyKey);
    if (historyJson == null) return {};
    final Map<String, dynamic> historyMap = json.decode(historyJson);
    return historyMap.map((key, value) => MapEntry(
          DateTime.parse(key),
          value as int,
        ));
  }

  @override
  Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakKey) ?? 0;
  }

  Future<int> _calculateStreak() async {
    final history = await getCompletionHistory();
    int streak = 0;
    DateTime today = DateTime.now();
    DateTime current = DateTime(today.year, today.month, today.day);
    while (history.containsKey(current)) {
      streak++;
      current = current.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

// BLoC
abstract class ExerciseEvent {}

class FetchExercises extends ExerciseEvent {}

class MarkExerciseCompleted extends ExerciseEvent {
  final String exerciseId;
  final DateTime date;
  MarkExerciseCompleted(this.exerciseId, this.date);
}

class ExerciseState {
  final List<Exercise> exercises;
  final List<String> completedExercises;
  final Map<DateTime, int> completionHistory;
  final int streak;
  final bool isLoading;
  final String? error;

  ExerciseState({
    this.exercises = const [],
    this.completedExercises = const [],
    this.completionHistory = const {},
    this.streak = 0,
    this.isLoading = false,
    this.error,
  });

  ExerciseState copyWith({
    List<Exercise>? exercises,
    List<String>? completedExercises,
    Map<DateTime, int>? completionHistory,
    int? streak,
    bool? isLoading,
    String? error,
  }) {
    return ExerciseState(
      exercises: exercises ?? this.exercises,
      completedExercises: completedExercises ?? this.completedExercises,
      completionHistory: completionHistory ?? this.completionHistory,
      streak: streak ?? this.streak,
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
      final history = await repository.getCompletionHistory();
      final streak = await repository.getStreak();
      emit(state.copyWith(
        exercises: exercises,
        completedExercises: completed,
        completionHistory: history,
        streak: streak,
        isLoading: false,
        error: null,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onMarkExerciseCompleted(MarkExerciseCompleted event, Emitter<ExerciseState> emit) async {
    await repository.markExerciseCompleted(event.exerciseId, event.date);
    final completed = await repository.getCompletedExercises();
    final history = await repository.getCompletionHistory();
    final streak = await repository.getStreak();
    emit(state.copyWith(
      completedExercises: completed,
      completionHistory: history,
      streak: streak,
    ));
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
            primaryColor: const Color(0xFF4CAF50), // Green
            colorScheme: ColorScheme.fromSwatch(
              primarySwatch: Colors.green,
              accentColor: const Color(0xFFFF9800), // Orange
              backgroundColor: const Color(0xFFF5F5F5), // Light gray
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Color(0xFF212121)),
              bodyMedium: TextStyle(color: Color(0xFF212121)),
              headlineSmall: TextStyle(color: Color(0xFF212121), fontWeight: FontWeight.bold),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            ),
            tabBarTheme: const TabBarThemeData(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: Color(0xFFFF9800), width: 2),
              ),
            ),
            cardTheme: const CardThemeData(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3), // Blue
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'ALETHEA HEALTH',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              letterSpacing: 1.2,
            ),
          ),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.fitness_center), text: 'Exercises'),
              Tab(icon: Icon(Icons.trending_up), text: 'Progress'),
              Tab(icon: Icon(Icons.schedule), text: 'Schedule'),
              Tab(icon: Icon(Icons.person), text: 'Profile'),
            ],
          ),
        ),
        body: SizedBox.expand(
          child: TabBarView(
            children: [
              const ExercisesTab(),
              const ProgressTab(),
              const ScheduleTab(),
              const ProfileTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class ExercisesTab extends StatelessWidget {
  const ExercisesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 150,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: const Center(
            child: Text(
              'ALETHEA HEALTH\nStay Fit, Stay Healthy',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Expanded(
          child: BlocBuilder<ExerciseBloc, ExerciseState>(
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
              if (state.exercises.isEmpty) {
                return const Center(child: Text('No exercises available'));
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_fire_department, color: Color(0xFFFF9800)),
                        const SizedBox(width: 8),
                        Text(
                          'Streak: ${state.streak} days',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF212121),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.exercises.length,
                      itemBuilder: (context, index) {
                        final exercise = state.exercises[index];
                        final isCompleted = state.completedExercises.contains(exercise.id);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: const Icon(Icons.fitness_center, color: Color(0xFF4CAF50)),
                            title: Text(
                              exercise.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCompleted ? Colors.grey : Colors.black,
                              ),
                            ),
                            subtitle: Text('${exercise.duration} seconds'),
                            trailing: isCompleted
                                ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
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
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
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
          context.read<ExerciseBloc>().add(MarkExerciseCompleted(widget.exercise.id, DateTime.now()));
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                borderRadius: const BorderRadius.all(Radius.circular(12)),
              ),
              child: Text(
                widget.exercise.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                child: ElevatedButton.icon(
                  onPressed: _startTimer,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Exercise', style: TextStyle(fontSize: 18)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExerciseBloc, ExerciseState>(
      builder: (context, state) {
        final totalExercises = state.exercises.length;
        final completedCount = state.completedExercises.length;
        final completionRate = totalExercises > 0 ? (completedCount / totalExercises * 100).toStringAsFixed(1) : '0.0';
        final history = state.completionHistory;
        final last7Days = List.generate(7, (index) => DateTime.now().subtract(Duration(days: index)))
            .reversed
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: const Text(
                  'Your Progress',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stats',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('Total Exercises: $totalExercises'),
                      Text('Completed: $completedCount'),
                      Text('Completion Rate: $completionRate%'),
                      const SizedBox(height: 16),
                      Text(
                        'Streak: ${state.streak} days',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekly Completions',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: history.isEmpty
                            ? const Center(child: Text('No completion data available'))
                            : BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  titlesData: FlTitlesData(
                                    show: true,
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (value, meta) {
                                          if (value.toInt() >= 0 && value.toInt() < last7Days.length) {
                                            final date = last7Days[value.toInt()];
                                            return Text(
                                              DateFormat('E').format(date),
                                              style: const TextStyle(fontSize: 12),
                                            );
                                          }
                                          return const Text('');
                                        },
                                      ),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 40,
                                        getTitlesWidget: (value, meta) => Text(
                                          value.toInt().toString(),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  barGroups: last7Days.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final date = entry.value;
                                    final count = history[DateTime(date.year, date.month, date.day)] ?? 0;
                                    return BarChartGroupData(
                                      x: index,
                                      barRods: [
                                        BarChartRodData(
                                          toY: count.toDouble(),
                                          color: const Color(0xFF4CAF50),
                                          width: 16,
                                          borderRadius: const BorderRadius.all(Radius.circular(4)),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ScheduleTab extends StatelessWidget {
  const ScheduleTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExerciseBloc, ExerciseState>(
      builder: (context, state) {
        final history = state.completionHistory;
        final today = DateTime.now();
        final days = List.generate(7, (index) => today.subtract(Duration(days: index)))
            .reversed
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: const Text(
                  'Your Schedule',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (days.isEmpty)
                const Center(child: Text('No schedule data available'))
              else
                ...days.map((date) {
                  final isCompleted = history.containsKey(DateTime(date.year, date.month, date.day));
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: Icon(
                        isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: isCompleted ? const Color(0xFF4CAF50) : Colors.grey,
                      ),
                      title: Text(DateFormat('EEEE, MMMM d').format(date)),
                      subtitle: Text(isCompleted ? 'Exercises completed' : 'No exercises completed'),
                    ),
                  );
                }).toList(),
            ],
          ),
        );
      },
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
            child: const Text(
              'Your Profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'User Info',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Name: Alex Doe'),
                  const Text('Goal: Stay Fit & Healthy'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                    ),
                    child: const Text(
                      'Quote: "A healthy body leads to a healthy mind."',
                      style: TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}