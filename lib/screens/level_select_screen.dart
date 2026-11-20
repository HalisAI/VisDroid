// SPDX-License-Identifier: MIT
/// Màn chọn level kiểu game: gradient indigo, header sao tổng, các thế giới
/// với lưới thẻ màn — khoá/không khoá, sao đạt được, màn hiện tại phát sáng.
/// Đây là điểm vào của tab "Mê cung".
library;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/settings.dart';
import '../core/vis_engine.dart';
import '../game/game_theme.dart';
import '../game/levels.dart';
import '../game/progress.dart';
import '../game/sprites.dart';
import 'maze_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({
    super.key,
    required this.engine,
    required this.appState,
    required this.progress,
  });

  final ScriptEngine engine;
  final AppState appState;
  final GameProgress progress;

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    SpriteSet.instance.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  Future<void> _openLevel(int index) async {
    if (!widget.progress.isUnlocked(index)) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MazeScreen(
          engine: widget.engine,
          appState: widget.appState,
          progress: widget.progress,
          levelIndex: index,
        ),
      ),
    );
    // Quay về: GameProgress tự notify → AnimatedBuilder build lại lưới sao.
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.progress,
      builder: (context, _) {
        final p = widget.progress;
        return Scaffold(
          backgroundColor: kGameBgTop,
          body: Container(
            decoration: const BoxDecoration(gradient: kGameBgGradient),
            child: SafeArea(
              child: Column(
                children: [
                  _header(p),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        for (final world in kGameWorlds) ...[
                          _worldHeader(world),
                          _worldGrid(world, p),
                          const SizedBox(height: 8),
                        ],
                        if (p.allDone)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Center(
                              child: Text(
                                t(context, S.gameAllDone),
                                textAlign: TextAlign.center,
                                style: gameStateStyle(kGameSuccess),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(GameProgress p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          if (_ready)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Image.asset('assets/game/robot.png', width: 46, height: 46),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MÊ CUNG', style: gameTitleStyle(26)),
                Text('VISCRIPT · DẠY LẬP TRÌNH QUA CHƠI',
                    style: TextStyle(
                      color: kGameAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                    )),
              ],
            ),
          ),
          // Tổng sao
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kGamePanel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kGamePanelBorder),
            ),
            child: Row(
              children: [
                Image.asset('assets/game/star.png', width: 18, height: 18),
                const SizedBox(width: 6),
                Text(
                  '${p.totalStars}/${p.maxStars}',
                  style: const TextStyle(
                    color: kGameText,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _worldHeader(GameWorld world) {
    final idx = kGameWorlds.indexOf(world);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kGameAccent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: kGameAccent, width: 1.4),
            ),
            child: Text(
              '${idx + 1}',
              style: const TextStyle(
                color: kGameAccent,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(world.name.toUpperCase(),
                    style: TextStyle(
                      color: kGameText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    )),
                Text(world.subtitle, style: gameDimStyle(11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _worldGrid(GameWorld world, GameProgress p) {
    final levels = [
      for (var i = 0; i < kGameLevels.length; i++)
        if (kGameLevels[i].world == world.id) i
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.92,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: levels.length,
      itemBuilder: (context, i) {
        final index = levels[i];
        return _LevelCard(
          level: kGameLevels[index],
          index: index,
          stars: p.starsOf(kGameLevels[index]),
          unlocked: p.isUnlocked(index),
          current: index == p.currentIndex,
          onTap: () => _openLevel(index),
        );
      },
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.index,
    required this.stars,
    required this.unlocked,
    required this.current,
    required this.onTap,
  });

  final int index;
  final int stars;
  final bool unlocked;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lv = level;
    return GestureDetector(
      onTap: unlocked ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: unlocked ? kGamePanel : kGamePanel.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: current
                ? kGameAccent
                : (unlocked ? kGamePanelBorder : kGamePanelBorder.withValues(alpha: 0.4)),
            width: current ? 2 : 1,
          ),
          boxShadow: current
              ? [BoxShadow(color: kGameAccent.withValues(alpha: 0.25), blurRadius: 14)]
              : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: unlocked
                        ? (current ? kGameAccent : kGameText)
                        : kGameTextDim.withValues(alpha: 0.5),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                if (!unlocked) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lock_outline,
                      size: 15, color: kGameTextDim.withValues(alpha: 0.7)),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                lv.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: unlocked ? kGameTextDim : kGameTextDim.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var s = 0; s < 3; s++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Image.asset(
                      s < stars
                          ? 'assets/game/star.png'
                          : 'assets/game/star_off.png',
                      width: 14,
                      height: 14,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
