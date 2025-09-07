import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:async';

class VocabularyGraphView extends StatefulWidget {
  final String language;
  final String searchQuery;
  const VocabularyGraphView({super.key, required this.language, required this.searchQuery});

  @override
  State<VocabularyGraphView> createState() => VocabularyGraphViewState();
}

class VocabularyGraphViewState extends State<VocabularyGraphView> {
  late CollectionReference _vocabularyCollection;
  
  // 노드와 에지 데이터
  final Map<String, NodeData> _nodes = {};
  final List<EdgeData> _edges = [];
  
  String? _selectedNodeId;
  bool _isInitialized = false;
  
  // 애니메이션 관련
  Timer? _physicsTimer;
  bool _isPhysicsRunning = false;
  DateTime? _lastInteractionTime;
  bool _hasSignificantChange = false;
  double _lastTotalEnergy = 0;
  int _stableFrameCount = 0;
  
  // 로딩 상태 관리
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _vocabularyCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection('vocabulary');
    
    // 초기 로드 시에만 물리 시뮬레이션 시작
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _nodes.isNotEmpty) {
        _startPhysicsSimulation();
      }
    });
  }

  @override
  void didUpdateWidget(VocabularyGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.language != oldWidget.language) {
      _vocabularyCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection('vocabulary');
      setState(() {
        _selectedNodeId = null;
        _nodes.clear();
        _edges.clear();
        _isInitialized = false;
      });
    }
  }
  
  @override
  void dispose() {
    _stopPhysicsSimulation();
    super.dispose();
  }
  
  void _startPhysicsSimulation() {
    if (_isPhysicsRunning || _nodes.isEmpty) return;
    
    _isPhysicsRunning = true;
    _lastInteractionTime = DateTime.now();
    _stableFrameCount = 0;
    
    // 50ms 주기로 부드러운 애니메이션과 성능의 균형
    _physicsTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updatePhysics();
      setState(() {});
    });
  }
  
  void _stopPhysicsSimulation() {
    _isPhysicsRunning = false;
    _physicsTimer?.cancel();
    _physicsTimer = null;
  }
  
  void _updatePhysics() {
    if (_nodes.isEmpty) return;
    
    // 노드 수에 따라 공간 크기 동적 조정
    final nodeCount = _nodes.length;
    final double boundarySize = (300 + (nodeCount * 30).toDouble()).clamp(300, 1000); // 300~1000 범위로 축소
    
    // 노드 수에 따라 물리 파라미터 조정
    final double springStrength = (0.05 - (nodeCount * 0.0005)).clamp(0.02, 0.05); // 노드가 많을수록 인력 감소
    final double repulsionStrength = 3000 + (nodeCount * 50).toDouble(); // 노드가 많을수록 척력 증가
    const double damping = 0.92; // 감쇠 계수
    const double maxVelocity = 8; // 최대 속도
    const double centerAttraction = 0.0005; // 중심으로의 약한 인력
    
    // 모든 노드에 대해 척력 계산
    for (final node1 in _nodes.values) {
      for (final node2 in _nodes.values) {
        if (node1.id == node2.id) continue;
        
        final dx = node2.x - node1.x;
        final dy = node2.y - node1.y;
        var distance = sqrt(dx * dx + dy * dy);
        
        if (distance < 1) distance = 1; // 0 분할 방지
        
        // 척력 (Coulomb's law)
        final force = repulsionStrength / (distance * distance);
        final fx = (dx / distance) * force;
        final fy = (dy / distance) * force;
        
        node1.vx -= fx;
        node1.vy -= fy;
      }
      
      // 중심으로의 약한 인력
      node1.vx -= node1.x * centerAttraction;
      node1.vy -= node1.y * centerAttraction;
    }
    
    // 연결된 노드들 간의 인력 계산
    for (final edge in _edges) {
      final node1 = _nodes[edge.fromId];
      final node2 = _nodes[edge.toId];
      
      if (node1 != null && node2 != null) {
        final dx = node2.x - node1.x;
        final dy = node2.y - node1.y;
        final distance = sqrt(dx * dx + dy * dy);
        
        // Hooke's law (스프링 힘)
        final fx = dx * springStrength;
        final fy = dy * springStrength;
        
        node1.vx += fx;
        node1.vy += fy;
        node2.vx -= fx;
        node2.vy -= fy;
      }
    }
    
    // 속도 업데이트 및 위치 업데이트
    double totalKineticEnergy = 0;
    
    for (final node in _nodes.values) {
      // 감쇠 적용
      node.vx *= damping;
      node.vy *= damping;
      
      // 최대 속도 제한
      final velocity = sqrt(node.vx * node.vx + node.vy * node.vy);
      if (velocity > maxVelocity) {
        node.vx = (node.vx / velocity) * maxVelocity;
        node.vy = (node.vy / velocity) * maxVelocity;
      }
      
      // 위치 업데이트
      node.x += node.vx;
      node.y += node.vy;
      
      // 경계 제한 (노드 수에 따라 동적 조정)
      node.x = node.x.clamp(-boundarySize, boundarySize);
      node.y = node.y.clamp(-boundarySize, boundarySize);
      
      // 운동 에너지 계산
      totalKineticEnergy += node.vx * node.vx + node.vy * node.vy;
    }
    
    // 운동 에너지 기반 안정화 감지
    const double energyThreshold = 0.5;
    const int requiredStableFrames = 60; // 3초간 안정 (50ms * 60)
    
    // 시스템이 안정화되면 물리 시뮬레이션 자동 중지
    if (totalKineticEnergy < energyThreshold && _nodes.length > 0) {
      _stableFrameCount++;
      
      if (_stableFrameCount >= requiredStableFrames) {
        // 5초 후 자동 중지
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _isPhysicsRunning && !_hasSignificantChange) {
            _stopPhysicsSimulation();
            _hasSignificantChange = false;
          }
        });
      }
    } else {
      _stableFrameCount = 0;
    }
    
    _lastTotalEnergy = totalKineticEnergy;
  }

  double get _canvasSize {
    // Flutter 웹에서 안전한 고정 크기로 설정
    return 2048.0; // 2048x2048로 줄임 (2^11, 웹 Canvas 안전 크기)
  }
  
  void _handleCanvasTap(Offset position) {
    final centerX = _canvasSize / 2;
    final centerY = _canvasSize / 2;
    
    bool nodeFound = false;
    
    for (final node in _nodes.values) {
      final nodeScreenPos = Offset(
        node.x + centerX,
        node.y + centerY,
      );
      
      final nodeRect = Rect.fromCenter(
        center: nodeScreenPos,
        width: 120,
        height: 40,
      );
      
      if (nodeRect.contains(position)) {
        _handleNodeTap(node.id);
        nodeFound = true;
        return;
      }
    }
    
    // 빈 공간을 클릭하면 선택 해제만 하고 시뮬레이션은 재시작하지 않음
    if (!nodeFound && _selectedNodeId != null) {
      setState(() {
        _selectedNodeId = null;
      });
    }
  }
  
  void _handleCanvasLongPress(Offset position) {
    final centerX = _canvasSize / 2;
    final centerY = _canvasSize / 2;
    
    for (final node in _nodes.values) {
      final nodeScreenPos = Offset(
        node.x + centerX,
        node.y + centerY,
      );
      
      final nodeRect = Rect.fromCenter(
        center: nodeScreenPos,
        width: 120,
        height: 40,
      );
      
      if (nodeRect.contains(position)) {
        _showDeleteConfirmationDialog(node.word, node.id);
        return;
      }
    }
  }

  Future<void> _deleteVocabulary(String docId) async {
    final doc = await _vocabularyCollection.doc(docId).get();
    final connections = List<String>.from((doc.data() as Map<String, dynamic>)['connections'] ?? []);

    final batch = FirebaseFirestore.instance.batch();

    for (var otherId in connections) {
        final otherNodeRef = _vocabularyCollection.doc(otherId);
        batch.update(otherNodeRef, {'connections': FieldValue.arrayRemove([docId])});
    }

    batch.delete(_vocabularyCollection.doc(docId));

    await batch.commit();

    setState(() {
      _selectedNodeId = null;
    });
    
    // 노드 삭제 시 물리 시뮬레이션 재시작
    _hasSignificantChange = true;
    _startPhysicsSimulation();
  }

  void _showDeleteConfirmationDialog(String word, String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$word"?'),
        content: const Text('Are you sure you want to delete this word and all its connections?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => _deleteVocabulary(docId).then((_) => Navigator.of(context).pop()),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showNodeInfoDialog(String word, String definition) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(word),
        content: SingleChildScrollView(child: Text(definition)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _handleNodeTap(String nodeId) async {
    final node = _nodes[nodeId];
    if (node == null) return;

    if (_selectedNodeId == nodeId) {
      _showNodeInfoDialog(node.word, node.definition);
      setState(() {
        _selectedNodeId = null;
      });
      return;
    }

    if (_selectedNodeId == null) {
      setState(() {
        _selectedNodeId = nodeId;
      });
      return;
    }

    // 연결 생성/제거
    final selectedNodeRef = _vocabularyCollection.doc(_selectedNodeId!);
    final doc = await selectedNodeRef.get();
    final connections = List<String>.from((doc.data() as Map<String, dynamic>)['connections'] ?? []);

    final batch = FirebaseFirestore.instance.batch();
    final tappedNodeRef = _vocabularyCollection.doc(nodeId);
    
    bool connectionChanged = false;

    if (connections.contains(nodeId)) {
      batch.update(selectedNodeRef, {'connections': FieldValue.arrayRemove([nodeId])});
      batch.update(tappedNodeRef, {'connections': FieldValue.arrayRemove([_selectedNodeId!])});
      connectionChanged = true;
    } else {
      batch.update(selectedNodeRef, {'connections': FieldValue.arrayUnion([nodeId])});
      batch.update(tappedNodeRef, {'connections': FieldValue.arrayUnion([_selectedNodeId!])});
      connectionChanged = true;
    }
    
    await batch.commit();
    
    // 연결이 변경되었을 때만 물리 시뮬레이션 재시작
    if (connectionChanged) {
      _hasSignificantChange = true;
      _startPhysicsSimulation();
    }
    
    setState(() {
      _selectedNodeId = null;
    });
  }

  void _updateNodesAndEdges(List<QueryDocumentSnapshot> docs) {
    final docMap = {for (var doc in docs) doc.id: doc.data() as Map<String, dynamic>};
    
    // 삭제된 노드 제거
    _nodes.removeWhere((id, node) => !docMap.containsKey(id));
    
    // 새로운 노드 추가 및 기존 노드 업데이트
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final docId = doc.id;
      
      if (_nodes.containsKey(docId)) {
        // 기존 노드 업데이트
        _nodes[docId]!.word = data['word'] ?? '[No Word]';
        _nodes[docId]!.definition = data['definition'] ?? '[No Definition]';
      } else {
        // 새 노드 추가 - 랜덤 위치
        final random = Random();
        final nodeCount = _nodes.length;
        final double spawnRange = (200 + (nodeCount * 10).toDouble()).clamp(200, 600); // 200~600 범위로 축소
        _nodes[docId] = NodeData(
          id: docId,
          word: data['word'] ?? '[No Word]',
          definition: data['definition'] ?? '[No Definition]',
          x: random.nextDouble() * spawnRange * 2 - spawnRange,
          y: random.nextDouble() * spawnRange * 2 - spawnRange,
          vx: 0,
          vy: 0,
        );
        
        // 새 노드가 추가되면 중요한 변화로 표시하고 물리 시뮬레이션 재시작
        _hasSignificantChange = true;
        _startPhysicsSimulation();
      }
    }
    
    // Force-directed 레이아웃 적용 (간단한 시뮬레이션)
    if (!_isInitialized && _nodes.isNotEmpty) {
      _applyForceDirectedLayout();
      _isInitialized = true;
    }
    
    // 에지 업데이트
    _edges.clear();
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final docId = doc.id;
      final connections = List<String>.from(data['connections'] ?? []);
      
      for (final connectedId in connections) {
        if (_nodes.containsKey(connectedId) && docId.compareTo(connectedId) < 0) {
          _edges.add(EdgeData(fromId: docId, toId: connectedId));
        }
      }
    }
  }

  void _applyForceDirectedLayout() {
    // 초기 레이아웃만 설정하고 실제 움직임은 _updatePhysics에서 처리
    for (final node in _nodes.values) {
      // 속도 초기화
      node.vx = 0;
      node.vy = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _vocabularyCollection.snapshots(),
      builder: (context, snapshot) {
        // 연결 상태 확인
        if (snapshot.connectionState == ConnectionState.waiting && _isFirstLoad) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Loading vocabulary...',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }
        
        // 에러 처리
        if (snapshot.hasError) {
          developer.log('Firestore Stream Error', error: snapshot.error, stackTrace: snapshot.stackTrace);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Oops! Something went wrong',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: ${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {});
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        
        // 빈 상태 처리
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          _nodes.clear();
          _edges.clear();
          if (_isFirstLoad) _isFirstLoad = false;
          
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No vocabulary yet',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your first word to get started!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    // 단어 추가 다이얼로그 열기 로직
                    // 부모 위젯에서 처리
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Word'),
                ),
              ],
            ),
          );
        }
        
        // 데이터 업데이트 및 렌더링
        _updateNodesAndEdges(snapshot.data!.docs);
        if (_isFirstLoad) _isFirstLoad = false;
        
        return LayoutBuilder(
          builder: (context, constraints) {
            // 제약 조건 확인 및 안전한 크기 설정
            final safeSize = _canvasSize.clamp(100.0, 2048.0);
            
            return InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(100),
              minScale: 0.1,
              maxScale: 3.0,
              child: SizedBox(
                width: safeSize,
                height: safeSize,
                child: GestureDetector(
                  onTapDown: (details) {
                    _handleCanvasTap(details.localPosition);
                  },
                  onLongPressStart: (details) {
                    _handleCanvasLongPress(details.localPosition);
                  },
                  child: CustomPaint(
                    size: Size(safeSize, safeSize),
                    painter: GraphPainter(
                      nodes: _nodes,
                      edges: _edges,
                      selectedNodeId: _selectedNodeId,
                      searchQuery: widget.searchQuery,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// 노드 데이터 클래스
class NodeData {
  final String id;
  String word;
  String definition;
  double x;
  double y;
  double vx; // 속도 x
  double vy; // 속도 y
  
  NodeData({
    required this.id,
    required this.word,
    required this.definition,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
  });
}

// 에지 데이터 클래스
class EdgeData {
  final String fromId;
  final String toId;
  
  EdgeData({required this.fromId, required this.toId});
}

// 그래프 페인터
class GraphPainter extends CustomPainter {
  final Map<String, NodeData> nodes;
  final List<EdgeData> edges;
  final String? selectedNodeId;
  final String searchQuery;
  
  GraphPainter({
    required this.nodes,
    required this.edges,
    required this.selectedNodeId,
    required this.searchQuery,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 안전한 크기 확인
    if (size.width <= 0 || size.height <= 0) return;
    
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    
    // 에지 그리기
    for (final edge in edges) {
      final fromNode = nodes[edge.fromId];
      final toNode = nodes[edge.toId];
      
      if (fromNode != null && toNode != null) {
        final isSelected = selectedNodeId == edge.fromId || selectedNodeId == edge.toId;
        
        final paint = Paint()
          ..color = isSelected ? Colors.tealAccent : Colors.grey.withOpacity(0.5)
          ..strokeWidth = isSelected ? 3.0 : 2.0
          ..style = PaintingStyle.stroke;
        
        canvas.drawLine(
          Offset(fromNode.x + centerX, fromNode.y + centerY),
          Offset(toNode.x + centerX, toNode.y + centerY),
          paint,
        );
      }
    }
    
    // 노드 그리기
    for (final node in nodes.values) {
      final isSelected = selectedNodeId == node.id;
      final isSearchResult = searchQuery.isNotEmpty && 
          node.word.toLowerCase().contains(searchQuery.toLowerCase());
      
      final nodePos = Offset(node.x + centerX, node.y + centerY);
      
      // 노드 스타일 (기존 디자인 복구)
      final bgColor = isSelected 
          ? Colors.blue 
          : isSearchResult
              ? Colors.yellow.withOpacity(0.8)
              : Colors.white;
      
      final borderColor = isSelected 
          ? Colors.white 
          : isSearchResult
              ? Colors.orange
              : Colors.blue;
      
      // 그림자
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: nodePos + const Offset(2, 2), width: 120, height: 40),
          const Radius.circular(20),
        ),
        shadowPaint,
      );
      
      // 노드 배경
      final bgPaint = Paint()..color = bgColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: nodePos, width: 120, height: 40),
          const Radius.circular(20),
        ),
        bgPaint,
      );
      
      // 노드 테두리
      final borderPaint = Paint()
        ..color = borderColor
        ..strokeWidth = isSearchResult ? 3 : 2
        ..style = PaintingStyle.stroke;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: nodePos, width: 120, height: 40),
          const Radius.circular(20),
        ),
        borderPaint,
      );
      
      // 텍스트
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.word,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      
      textPainter.layout(maxWidth: 100);
      textPainter.paint(
        canvas,
        Offset(
          nodePos.dx - textPainter.width / 2,
          nodePos.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
  
  @override
  bool hitTest(Offset position) => true;
}
