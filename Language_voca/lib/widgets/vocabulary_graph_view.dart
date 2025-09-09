import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:async';

class VocabularyGraphView extends StatefulWidget {
  final String language;
  final String searchQuery;
  final String? collectionName; // New parameter
  final bool isTopLevelCollection; // Med_voca 같은 최상위 컬렉션인지 표시
  const VocabularyGraphView({
    super.key, 
    required this.language, 
    required this.searchQuery, 
    this.collectionName,
    this.isTopLevelCollection = false,
  }); // Updated constructor

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
  
  // 최적화: 한 번만 로드하고 캐싱
  List<QueryDocumentSnapshot>? _cachedDocs;
  StreamSubscription? _streamSubscription;
  
  // InteractiveViewer 상태 유지
  final TransformationController _transformationController = TransformationController();
  
  // CustomPainter만 다시 그리기 위한 ValueNotifier
  final ValueNotifier<int> _repaintNotifier = ValueNotifier<int>(0);
  
  // 뷰포트 기반 렌더링을 위한 현재 뷰포트
  Rect _currentViewport = Rect.zero;
  
  // 성능 최적화: 노드 수 제한
  static const int MAX_VISIBLE_NODES = 200; // 한 번에 보이는 최대 노드 수
  static const int INITIAL_LOAD_LIMIT = 300; // 초기 로드 제한
  static const int LOAD_MORE_BATCH = 100; // 추가 로드 배치 크기
  
  // 페이지네이션 상태
  bool _isLoadingMore = false;
  bool _hasMoreToLoad = true;
  DocumentSnapshot? _lastDocument;
  
  // 초기 카메라 위치 설정 여부
  bool _initialCameraSet = false;

  @override
  void initState() {
    super.initState();
    // isTopLevelCollection이 true면 최상위 컬렉션, false면 language 하위 컬렉션
    if (widget.isTopLevelCollection) {
      _vocabularyCollection = FirebaseFirestore.instance.collection(widget.collectionName ?? 'Med_voca');
    } else {
      _vocabularyCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection(widget.collectionName ?? 'vocabulary');
    }
    
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
    if (widget.language != oldWidget.language || widget.collectionName != oldWidget.collectionName || widget.isTopLevelCollection != oldWidget.isTopLevelCollection) { // Check all
      // isTopLevelCollection에 따라 컬렉션 경로 결정
      if (widget.isTopLevelCollection) {
        _vocabularyCollection = FirebaseFirestore.instance.collection(widget.collectionName ?? 'Med_voca');
      } else {
        _vocabularyCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection(widget.collectionName ?? 'vocabulary');
      }
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
    _streamSubscription?.cancel();
    _stopPhysicsSimulation();
    _transformationController.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }
  
  void _startPhysicsSimulation({Duration? runFor}) {
    if (_isPhysicsRunning || _nodes.isEmpty) return;
    
    _isPhysicsRunning = true;
    _lastInteractionTime = DateTime.now();
    _stableFrameCount = 0;
    
    // 삭제와 같이 짧은 시간만 실행해야 할 경우, 타이머로 자동 중지
    if (runFor != null) {
      Timer(runFor, () {
        if (mounted && _isPhysicsRunning) {
          _stopPhysicsSimulation();
          _hasSignificantChange = false; // 플래그 리셋
        }
      });
    }
    
    // 50ms 주기로 부드러운 애니메이션과 성능의 균형
    _physicsTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updatePhysics();
      // setState 제거 - 물리 시뮬레이션은 그냥 돌아가게 둠
      _repaintNotifier.value++;
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
    // 대규모 노드를 위한 더 넓은 경계
    double boundarySize;
    if (nodeCount <= 100) {
      boundarySize = 500 + (nodeCount * 20);
    } else if (nodeCount <= 500) {
      boundarySize = 2500 + ((nodeCount - 100) * 15);
    } else if (nodeCount <= 1000) {
      boundarySize = 8500 + ((nodeCount - 500) * 10);
    } else {
      boundarySize = 13500 + ((nodeCount - 1000) * 5);
    }
    // 최대 20000으로 제한
    boundarySize = boundarySize.clamp(500, 20000);
    
    // 노드 수에 따라 물리 파라미터 조정
    final double springStrength = (0.04 - (nodeCount * 0.0003)).clamp(0.015, 0.04); // 인력 감소
    final double repulsionStrength = 2500 + (nodeCount * 30).toDouble(); // 척력 적절히 조정
    const double damping = 0.88; // 감쇠 계수 조정
    const double maxVelocity = 6; // 최대 속도 감소
    const double centerAttraction = 0.0003; // 중심 인력 감소
    
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
    const double energyThreshold = 0.3; // 임계값을 낮춰 더 빨리 안정화
    const int requiredStableFrames = 10; // 0.5초간 안정 (50ms * 10)
    
    // 시스템이 안정화되면 물리 시뮬레이션 자동 중지
    if (totalKineticEnergy < energyThreshold && _nodes.length > 0) {
      _stableFrameCount++;
      
      if (_stableFrameCount >= requiredStableFrames) {
        // 즉시 중지
        if (mounted && _isPhysicsRunning && !_hasSignificantChange) {
          _stopPhysicsSimulation();
          _hasSignificantChange = false;
        }
      }
    } else {
      _stableFrameCount = 0;
    }
    
    _lastTotalEnergy = totalKineticEnergy;
  }

  double get _canvasSize {
    // 노드 수에 따라 동적으로 크기 조정
    final nodeCount = _nodes.length;
    
    // 단계별 크기 설정 (2000개까지 안전하게)
    double dynamicSize;
    if (nodeCount <= 100) {
      // 100개까지: 노드당 50px (여유롭게)
      dynamicSize = 2000 + (nodeCount * 50);
    } else if (nodeCount <= 500) {
      // 101-500개: 노드당 35px
      dynamicSize = 7000 + ((nodeCount - 100) * 35);
    } else if (nodeCount <= 1000) {
      // 501-1000개: 노드당 25px
      dynamicSize = 21000 + ((nodeCount - 500) * 25);
    } else if (nodeCount <= 2000) {
      // 1001-2000개: 노드당 15px
      dynamicSize = 33500 + ((nodeCount - 1000) * 15);
    } else {
      // 2000개 초과: 최대값 고정
      dynamicSize = 48500;
    }
    
    // 최소 2000, 최대 50000 (2000개 노드 기준)
    return dynamicSize.clamp(2000, 50000);
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
    
    // 빈 공간을 클릭하면 선택 해제
    if (!nodeFound && _selectedNodeId != null) {
      _selectedNodeId = null;
      _repaintNotifier.value++; // 선택 해제 시각화
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
    
    // connections 필드를 안전하게 처리
    List<String> connections = [];
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        final connData = data['connections'];
        if (connData is List) {
          connections = connData.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      connections = [];
    }

    final batch = FirebaseFirestore.instance.batch();

    for (var otherId in connections) {
        final otherNodeRef = _vocabularyCollection.doc(otherId);
        batch.update(otherNodeRef, {'connections': FieldValue.arrayRemove([docId])});
    }

    batch.delete(_vocabularyCollection.doc(docId));

    await batch.commit();

    // 로컬 상태에서 노드 직접 제거 (재렌더링 최소화)
    if (_nodes.containsKey(docId)) {
      _nodes.remove(docId);
      // 관련 엣지도 제거
      _edges.removeWhere((edge) => edge.fromId == docId || edge.toId == docId);
    }
    _selectedNodeId = null;
    
    // 노드 삭제 시 물리 시뮬레이션을 짧게 실행하여 주변만 재배치
    _hasSignificantChange = true;
    _startPhysicsSimulation(runFor: const Duration(milliseconds: 500));
    _repaintNotifier.value++; // 그래프만 다시 그리기
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

  void _showNodeInfoDialog(String nodeId, String word, String definition) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(word),
        content: SingleChildScrollView(child: Text(definition)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showEditNodeDialog(nodeId, word, definition);
            },
            child: const Text('Edit'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showEditNodeDialog(String nodeId, String currentWord, String currentDefinition) {
    final TextEditingController wordController = TextEditingController(text: currentWord);
    final TextEditingController definitionController = TextEditingController(text: currentDefinition);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Word'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordController,
                decoration: const InputDecoration(
                  labelText: 'Word',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: definitionController,
                decoration: const InputDecoration(
                  labelText: 'Definition',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                minLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newWord = wordController.text.trim();
              final newDefinition = definitionController.text.trim();
              
              if (newWord.isNotEmpty && newDefinition.isNotEmpty) {
                try {
                  // Update the document in Firestore
                  await _vocabularyCollection.doc(nodeId).update({
                    'word': newWord,
                    'definition': newDefinition,
                  });
                  
                  // Update the local node data
                  if (_nodes.containsKey(nodeId)) {
                    // 로컬 상태에서 직접 수정 (재렌더링 최소화)
                    _nodes[nodeId]!.word = newWord;
                    _nodes[nodeId]!.definition = newDefinition;
                    _repaintNotifier.value++; // 노드 텍스트만 업데이트
                  }
                  
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Word updated successfully'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating word: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNodeTap(String nodeId) async {
    final node = _nodes[nodeId];
    if (node == null) return;

    if (_selectedNodeId == nodeId) {
      _showNodeInfoDialog(nodeId, node.word, node.definition);
      _selectedNodeId = null;
      _repaintNotifier.value++; // 선택 해제 시각화
      return;
    }

    if (_selectedNodeId == null) {
      _selectedNodeId = nodeId;
      _repaintNotifier.value++; // 선택 시각화
      return;
    }

    // 연결 생성/제거
    final selectedNodeRef = _vocabularyCollection.doc(_selectedNodeId!);
    final doc = await selectedNodeRef.get();
    
    // connections 필드를 안전하게 처리
    List<String> connections = [];
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        final connData = data['connections'];
        if (connData is List) {
          connections = connData.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      connections = [];
    }

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
    
    // 연결이 변경되었을 때 로컬 엣지 업데이트
    if (connectionChanged) {
      // 엣지 목록을 로컬에서 직접 업데이트
      if (connections.contains(nodeId)) {
        // 연결 제거
        _edges.removeWhere((edge) => 
          (edge.fromId == _selectedNodeId && edge.toId == nodeId) ||
          (edge.fromId == nodeId && edge.toId == _selectedNodeId));
      } else {
        // 연결 추가 (중복 방지를 위해 정렬된 순서로)
        if (_selectedNodeId!.compareTo(nodeId) < 0) {
          _edges.add(EdgeData(fromId: _selectedNodeId!, toId: nodeId));
        } else {
          _edges.add(EdgeData(fromId: nodeId, toId: _selectedNodeId!));
        }
      }
      
      // 연결 변경 시 물리 시뮬레이션 재시작
      _hasSignificantChange = true;
      _startPhysicsSimulation();
      _repaintNotifier.value++; // 엣지만 다시 그리기
    }
    
    _selectedNodeId = null;
    _repaintNotifier.value++; // 선택 해제 시각화
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
        // 새 노드 추가 - 기존 노드들의 평균 위치 근처에 배치
        double avgX = 0;
        double avgY = 0;
        if (_nodes.isNotEmpty) {
          for (final node in _nodes.values) {
            avgX += node.x;
            avgY += node.y;
          }
          avgX /= _nodes.length;
          avgY /= _nodes.length;
        }
        
        final random = Random();
        // 평균 위치 근처에 작은 랜덤 오프셋으로 배치
        final double offsetRange = 100;
        _nodes[docId] = NodeData(
          id: docId,
          word: data['word'] ?? '[No Word]',
          definition: data['definition'] ?? '[No Definition]',
          x: avgX + (random.nextDouble() * offsetRange * 2 - offsetRange),
          y: avgY + (random.nextDouble() * offsetRange * 2 - offsetRange),
          vx: 0,
          vy: 0,
        );
        
        // 새 노드가 추가되면 물리 시뮬레이션 재시작하지 않음
        // _hasSignificantChange = true;
        // _startPhysicsSimulation();
      }
    }
    
    // Force-directed 레이아웃 적용 (간단한 시뮬레이션)
    if (!_isInitialized && _nodes.isNotEmpty) {
      _applyForceDirectedLayout();
      _isInitialized = true;
      
      // 초기 로드 시 카메라를 노드 중심부로 이동
      if (!_initialCameraSet && _nodes.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _centerCameraOnNodes();
        });
      }
    }
    
    // 에지 업데이트
    _edges.clear();
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final docId = doc.id;
      
      // connections 필드를 더 안전하게 처리
      List<String> connections = [];
      try {
        final connData = data['connections'];
        if (connData != null) {
          if (connData is List) {
            connections = connData.map((e) => e.toString()).toList();
          } else if (connData is String) {
            // String인 경우 빈 리스트로 처리
            connections = [];
          }
        }
      } catch (e) {
        // 오류 발생 시 빈 리스트
        connections = [];
      }
      
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
  
  void _centerCameraOnNodes() {
    if (!mounted || _initialCameraSet) return;

    // 뷰포트의 중심을 가져옴
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final viewSize = renderBox.size;
    final viewCenterX = viewSize.width / 2;
    final viewCenterY = viewSize.height / 2;

    // 캔버스 중심 (노드 좌표계의 0,0)을 뷰포트 중심으로 이동
    final canvasCenterX = _canvasSize / 2;
    final canvasCenterY = _canvasSize / 2;

    final matrix = Matrix4.identity()
      ..translate(viewCenterX - canvasCenterX, viewCenterY - canvasCenterY);

    _transformationController.value = matrix;
    _initialCameraSet = true;
  }

  @override
  Widget build(BuildContext context) {
    // 편집 모드나 연결 작업 중일 때만 실시간 업데이트 사용
    final bool useRealtimeUpdates = _selectedNodeId != null || _nodes.isEmpty;
    
    if (useRealtimeUpdates) {
      // 실시간 업데이트가 필요한 경우
      return StreamBuilder<QuerySnapshot>(
        stream: _vocabularyCollection
            .limit(INITIAL_LOAD_LIMIT)  // 초기 로드 제한
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _cachedDocs = snapshot.data!.docs;
          }
          return _buildGraphWidget(context, snapshot);
        },
      );
    } else {
      // 일반 보기 모드: 캐시된 데이터 사용 또는 한 번만 로드
      if (_cachedDocs != null) {
        // 캐시된 데이터가 있으면 바로 렌더링
        _updateNodesAndEdges(_cachedDocs!);
        return _buildGraphFromCache();
      } else {
        // 처음 로드할 때 FutureBuilder 사용
        return FutureBuilder<QuerySnapshot>(
          future: _vocabularyCollection
              .limit(INITIAL_LOAD_LIMIT)  // 초기 로드 제한
              .get(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _cachedDocs = snapshot.data!.docs;
            }
            return _buildGraphWidget(context, snapshot);
          },
        );
      }
    }
  }
  
  Widget _buildGraphWidget(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
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
            // 캔버스 크기 안전 확인
            final canvasSize = _canvasSize;
            final safeSize = canvasSize.clamp(1000.0, 50000.0);  // 최대 50000까지 허용
            
            return InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(100),
              minScale: 0.05,  // 더 많이 축소 가능
              maxScale: 5.0,    // 더 많이 확대 가능
              child: RepaintBoundary(  // 성능 최적화
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
                    child: ValueListenableBuilder<int>(
                      valueListenable: _repaintNotifier,
                      builder: (context, value, child) {
                        return CustomPaint(
                          size: Size(safeSize, safeSize),
                          painter: GraphPainter(
                            nodes: _nodes,
                            edges: _edges,
                            selectedNodeId: _selectedNodeId,
                            searchQuery: widget.searchQuery,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
  }
  
  Widget _buildGraphFromCache() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = _canvasSize;
        final safeSize = canvasSize.clamp(1000.0, 50000.0);  // 최대 50000까지 허용
        
        return InteractiveViewer(
          transformationController: _transformationController,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(100),
          minScale: 0.05,
          maxScale: 5.0,
          child: RepaintBoundary(
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
                child: ValueListenableBuilder<int>(
                  valueListenable: _repaintNotifier,
                  builder: (context, value, child) {
                    return CustomPaint(
                      size: Size(safeSize, safeSize),
                      painter: GraphPainter(
                        nodes: _nodes,
                        edges: _edges,
                        selectedNodeId: _selectedNodeId,
                        searchQuery: widget.searchQuery,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
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