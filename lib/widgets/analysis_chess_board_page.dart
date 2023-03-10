import 'package:chess_collections/widgets/analysis_chess_board_controller.dart';
import 'package:chess_pgn_parser/chess_pgn_parser.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:logging/logging.dart';

import 'import_pgn_dialog.dart';
import '../util/linear_chess_sequence.dart';

final _logger = Logger('home_page');

class AnalysisChessBoardPage extends StatefulWidget {
  static final _globalKey = GlobalKey();

  AnalysisChessBoardPage() : super(key: _globalKey);

  @override
  State<AnalysisChessBoardPage> createState() => _AnalysisChessBoardPageState();
}

class _AnalysisChessBoardPageState extends State<AnalysisChessBoardPage> {
  GameWithVariations? game;
  late AnalysisChessBoardController controller;
  bool _immportPgnDialogOpen = false;

  @override
  void initState() {
    super.initState();

    controller = AnalysisChessBoardController();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (game == null && mounted) _importPgn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ChessCollectionsAppBar(
        onPgnImportPressed: _importPgn,
      ),
      body: Focus(
        onKeyEvent: _onKeyEvent,
        child: ValueListenableBuilder<AnalysisChessBoardState>(
          valueListenable: controller,
          builder: (context, state, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChessBoard(
                controller: controller.chessBoardController,
                boardColor: BoardColor.orange,
                boardOrientation: PlayerColor.white,
              ),
              Expanded(
                child: ChessMoveHistory(
                  analysisChessBoardController: controller,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _importPgn() async {
    if (_immportPgnDialogOpen) {
      _logger.info('ImportPgnDialog is already open, ignoring request');
      return;
    }
    setState(() => _immportPgnDialogOpen = true);
    final importedGame = await _showImportDialogPgn();
    setState(() => _immportPgnDialogOpen = false);
    _logger.info(
        'The imported games are (choosing the first game):\n$importedGame');
    controller.loadGame(importedGame?.firstOrNull);
  }

  Future<List<GameWithVariations>?> _showImportDialogPgn() {
    return showDialog<List<GameWithVariations>>(
      context: context,
      builder: (BuildContext context) => const ImportPgnDialog(),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _logger.info('Left key pressed');
        controller.goBackIfPossible();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _logger.info('Right key pressed');
        if (controller.currentNode != null &&
            controller.currentNode!.children.isNotEmpty) {
          controller.goForward(controller.currentNode!.children.first);
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

class ChessCollectionsAppBar extends AppBar {
  ChessCollectionsAppBar({
    required VoidCallback onPgnImportPressed,
    Key? key,
  }) : super(
          title: const Text('Chess Collections'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.file_open),
              onPressed: onPgnImportPressed,
            )
          ],
          key: key,
        );
}

class ChessMoveHistory extends StatelessWidget {
  final AnalysisChessBoardController analysisChessBoardController;

  const ChessMoveHistory({
    required this.analysisChessBoardController,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return analysisChessBoardController.game == null
        ? Container()
        : ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _generateRows(),
                ),
              ),
            ),
          );
  }

  List<Widget> _generateRows() {
    List<LinearChessMoveSequence> linearChessMoveSequences =
        breakDownToLinearChessSequences(analysisChessBoardController.game!);

    _logger.info(
        'Linear chess move sequences:\n${linearChessMoveSequences.join('\n')}');

    return linearChessMoveSequences
        .map((item) => LinearChessMoveSequenceWidget(
              analysisChessBoardController: analysisChessBoardController,
              linearChessMoveSequence: item,
            ))
        .toList();
  }
}

class LinearChessMoveSequenceWidget extends StatelessWidget {
  final AnalysisChessBoardController analysisChessBoardController;
  final LinearChessMoveSequence linearChessMoveSequence;

  const LinearChessMoveSequenceWidget({
    required this.analysisChessBoardController,
    required this.linearChessMoveSequence,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12 * linearChessMoveSequence.depth.toDouble(),
        bottom: 8,
      ),
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 8,
        children: linearChessMoveSequence.sequence.map((item) {
          return ChessMove(
            analysisChessBoardController: analysisChessBoardController,
            node: item.node,
            board: item.board,
          );
        }).toList(),
      ),
    );
  }
}

class ChessMove extends StatelessWidget {
  final AnalysisChessBoardController analysisChessBoardController;
  static const _moveNumberTextStyle = TextStyle(fontWeight: FontWeight.bold);

  final GameNode node;
  final Chess board;

  ChessMove({
    required this.analysisChessBoardController,
    required this.node,
    required this.board,
    Key? key,
  })  : assert(!node.rootNode),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: analysisChessBoardController.currentNode == node
          ? Colors.black12
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => analysisChessBoardController.goTo(node, board),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show the move number indicator only for white moves and for
              // first moves after a decision point
              if (node.move!.color == Color.WHITE ||
                  node.parent!.children.length > 1)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    node.move!.moveNumberIndicator,
                    style: _moveNumberTextStyle,
                  ),
                ),
              Text(node.move!.san),
            ],
          ),
        ),
      ),
    );
  }
}
