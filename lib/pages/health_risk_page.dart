import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ml_prediction_service.dart';
import '../services/database_service.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';

/// Health Risk Assessment Page - Shows ML predictions
class HealthRiskPage extends ConsumerStatefulWidget {
  const HealthRiskPage({Key? key}) : super(key: key);

  @override
  ConsumerState<HealthRiskPage> createState() => _HealthRiskPageState();
}

class _HealthRiskPageState extends ConsumerState<HealthRiskPage> {
  final MLPredictionService _mlService = MLPredictionService();
  final DatabaseService _dbService = DatabaseService();
  
  bool _isLoading = false;
  bool _serverAvailable = false;
  HealthRiskPrediction? _prediction;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkServerAndPredict();
  }

  Future<void> _checkServerAndPredict() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check if ML server is running
      _serverAvailable = await _mlService.checkServerHealth();
      
      if (!_serverAvailable) {
        setState(() {
          _error = 'ML server is not running. Please start the FastAPI server.';
          _isLoading = false;
        });
        return;
      }

      // Get user data
      final user = ref.read(currentUserProvider);
      if (user == null) {
        setState(() {
          _error = 'User not logged in';
          _isLoading = false;
        });
        return;
      }

      // Get lifestyle data from last 7 days
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      
      // Get all user data and filter by date range
      final allHydrationLogs = _dbService.getUserHydrationLogs(user.id);
      final hydrationLogs = allHydrationLogs.where((log) =>
        log.timestamp.isAfter(weekAgo) && log.timestamp.isBefore(now)
      ).toList();
      
      final allMoodLogs = _dbService.getUserMoodLogs(user.id);
      final moodLogs = allMoodLogs.where((log) =>
        log.timestamp.isAfter(weekAgo) && log.timestamp.isBefore(now)
      ).toList();
      
      final allSymptoms = _dbService.getUserSymptoms(user.id);
      final symptoms = allSymptoms.where((symptom) =>
        symptom.timestamp.isAfter(weekAgo) && symptom.timestamp.isBefore(now)
      ).toList();

      // Get workout data from last 7 days
      final workouts = _dbService.getUserWorkoutsByDateRange(user.id, weekAgo, now);
      final totalExerciseMinutes = workouts.fold<double>(
        0.0, 
        (sum, workout) => sum + workout.durationMinutes.toDouble()
      );
      final avgDailyExercise = workouts.isNotEmpty ? (totalExerciseMinutes / 7).round() : 0;
      final avgIntensity = workouts.isNotEmpty 
        ? (workouts.map((w) => w.caloriesBurned).reduce((a, b) => a + b) / workouts.length / 10).round()
        : 5;

      // Get prediction
      final prediction = await _mlService.predictHealthRisk(
        user: user,
        hydrationLogs: hydrationLogs,
        moodLogs: moodLogs,
        symptoms: symptoms,
        exerciseDuration: avgDailyExercise,
        exerciseIntensity: avgIntensity.clamp(1, 10),
        sleepHours: 7.0, // TODO: Get from actual sleep logs if available
      );

      setState(() {
        _prediction = prediction;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error getting prediction: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Risk Assessment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkServerAndPredict,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _prediction != null
                  ? _buildPredictionView()
                  : const Center(child: Text('No data available')),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (!_serverAvailable) ...[
              const Text(
                'To start the ML server, run:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  'cd /Users/gitanjanganai/Downloads/NovaHealth\n'
                  'source ml_venv/bin/activate\n'
                  'python fastapi_server.py',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkServerAndPredict,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionView() {
    final prediction = _prediction!;
    final obesity = prediction.obesityRisk;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall Risk Score Card
          _buildRiskScoreCard(prediction.overallRiskScore),
          
          const SizedBox(height: 16),
          
          // Key Insights
          _buildKeyInsights(prediction.keyInsights),
          
          const SizedBox(height: 16),
          
          // Symptom Risk Analysis (if available)
          if (prediction.symptomRiskAnalysis != null)
            _buildSymptomRiskCard(prediction.symptomRiskAnalysis!),
          
          if (prediction.symptomRiskAnalysis != null)
            const SizedBox(height: 16),
          
          // Obesity Risk Card
          _buildObesityRiskCard(obesity),
          
          const SizedBox(height: 16),
          
          // Exercise Recommendation (if available)
          if (prediction.exerciseRecommendation != null)
            _buildExerciseCard(prediction.exerciseRecommendation!),
          
          const SizedBox(height: 16),
          
          // Recommendations
          _buildRecommendations(obesity.recommendations),
        ],
      ),
    );
  }

  Widget _buildRiskScoreCard(double score) {
    Color color;
    String level;
    
    if (score < 30) {
      color = Colors.green;
      level = 'Low Risk';
    } else if (score < 60) {
      color = Colors.orange;
      level = 'Moderate Risk';
    } else {
      color = Colors.red;
      level = 'High Risk';
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Overall Health Risk',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 12,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '${score.toInt()}',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      level,
                      style: TextStyle(
                        fontSize: 16,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyInsights(List<String> insights) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '💡 Key Insights',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...insights.map((insight) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 16)),
                  Expanded(child: Text(insight)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildObesityRiskCard(ObesityRiskResult obesity) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚖️ Weight & BMI Analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Risk Level', obesity.riskLevelDisplay),
            _buildInfoRow('BMI', obesity.bmi.toStringAsFixed(1)),
            _buildInfoRow('BMR', '${obesity.bmr.toStringAsFixed(0)} cal/day'),
            _buildInfoRow('Confidence', '${(obesity.confidence * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 12),
            const Text(
              'Risk Distribution:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...obesity.allProbabilities.entries.map((entry) {
              final percentage = (entry.value * 100).toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(entry.key.replaceAll('_', ' ')),
                    ),
                    Expanded(
                      flex: 2,
                      child: LinearProgressIndicator(
                        value: entry.value,
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('$percentage%', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(ExerciseRecommendation exercise) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🏃 Exercise Analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Calories Burned', '${exercise.predictedCalories.toStringAsFixed(0)} cal'),
            _buildInfoRow('Calories/Minute', exercise.caloriesPerMinute.toStringAsFixed(1)),
            _buildInfoRow('MET Score', exercise.metScore.toStringAsFixed(1)),
            _buildInfoRow('Intensity', exercise.intensityLevel),
          ],
        ),
      ),
    );
  }

  Widget _buildSymptomRiskCard(SymptomRiskAnalysis analysis) {
    Color riskColor;
    IconData riskIcon;
    
    switch (analysis.riskLevel) {
      case 'Critical':
        riskColor = Colors.red[900]!;
        riskIcon = Icons.error;
        break;
      case 'High':
        riskColor = Colors.red;
        riskIcon = Icons.warning;
        break;
      case 'Moderate':
        riskColor = Colors.orange;
        riskIcon = Icons.info;
        break;
      default:
        riskColor = Colors.blue;
        riskIcon = Icons.check_circle;
    }
    
    return Card(
      color: riskColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(riskIcon, color: riskColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🩺 Symptom Risk Analysis',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: riskColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Risk Level
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: riskColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Risk Level: ${analysis.riskLevel}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Urgency
            Text(
              '⏰ ${analysis.urgency}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: riskColor,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Probable Conditions
            const Text(
              'Probable Health Conditions:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ...analysis.probableConditions.map((condition) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.medical_services, color: riskColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      condition,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            )),
            
            const SizedBox(height: 16),
            
            // Detected Symptoms
            const Text(
              'Detected Symptoms:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ...analysis.detectedSymptoms.map((symptom) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${symptom['type']} (Severity: ${symptom['severity']}/10)',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations(List<String> recommendations) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📋 Personalized Recommendations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...recommendations.map((rec) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(rec)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
