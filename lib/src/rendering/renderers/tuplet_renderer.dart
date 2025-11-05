// lib/src/rendering/renderers/tuplet_renderer.dart

import 'package:flutter/material.dart';
import '../../../core/core.dart'; // Tipos do core
import '../../smufl/smufl_metadata_loader.dart';
import '../../theme/music_score_theme.dart';
import '../staff_coordinate_system.dart';
import 'note_renderer.dart';
import 'rest_renderer.dart';

/// Renderizador especializado para grupos de tercina e outras quiáltera
class TupletRenderer {
  final StaffCoordinateSystem coordinates;
  final SmuflMetadata metadata;
  final MusicScoreTheme theme;
  final double glyphSize;
  final NoteRenderer noteRenderer;
  final RestRenderer restRenderer;

  TupletRenderer({
    required this.coordinates,
    required this.metadata,
    required this.theme,
    required this.glyphSize,
    required this.noteRenderer,
    required this.restRenderer,
  });

  void render(
    Canvas canvas,
    Tuplet tuplet,
    Offset basePosition,
    Clef currentClef,
  ) {
    double currentX = basePosition.dx;
    // CORREÇÃO: Aumentar espaçamento para evitar sobreposição
    final spacing = coordinates.staffSpace * 2.5; // Era 1.2, agora 2.5
    final List<Offset> notePositions = [];

    // Renderizar elementos individuais do tuplet
    for (final element in tuplet.elements) {
      if (element is Note) {
        noteRenderer.render(
          canvas,
          element,
          Offset(currentX, basePosition.dy),
          currentClef,
        );
        notePositions.add(Offset(currentX, basePosition.dy));
        currentX += spacing;
      } else if (element is Rest) {
        restRenderer.render(
          canvas,
          element,
          Offset(currentX, basePosition.dy),
        );
        notePositions.add(Offset(currentX, basePosition.dy));
        currentX += spacing;
      }
    }

    // Desenhar colchete se necessário
    if (tuplet.showBracket && notePositions.length >= 2) {
      _drawTupletBracket(canvas, notePositions, tuplet.actualNotes);
    }

    // Desenhar número
    if (tuplet.showNumber && notePositions.isNotEmpty) {
      _drawTupletNumber(canvas, notePositions, tuplet.actualNotes);
    }
  }

  void _drawTupletBracket(
    Canvas canvas,
    List<Offset> notePositions,
    int number,
  ) {
    if (notePositions.length < 2) return;

    final firstNote = notePositions.first;
    final lastNote = notePositions.last;
    
    // CORREÇÃO: Altura do bracket baseada em EngravingRules (tupletBracketHeight = 1.0)
    // Posicionar acima das hastes com clearance adequado
    final bracketY = firstNote.dy - (coordinates.staffSpace * 4.0); // Aumentado de 2.5

    // CORREÇÃO SMuFL: Espessura consistente com tupletLineWidth (0.12 staff spaces)
    final paint = Paint()
      ..color = theme.stemColor
      ..strokeWidth = coordinates.staffSpace * 0.12 // Aumentado de 0.08
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square; // Pontas quadradas

    // Calcular largura do grupo
    final groupWidth = (lastNote.dx - firstNote.dx).abs();
    
    // CORREÇÃO: Bracket proporcional - não precisa cobrir toda a extensão
    // Deixar espaço para o número no centro (30% no meio livre)
    
    // Linha horizontal esquerda
    canvas.drawLine(
      Offset(firstNote.dx, bracketY),
      Offset(firstNote.dx + (groupWidth * 0.35), bracketY), // 35% da largura
      paint,
    );
    
    // Linha horizontal direita
    canvas.drawLine(
      Offset(lastNote.dx - (groupWidth * 0.35), bracketY), // 35% da largura
      Offset(lastNote.dx, bracketY),
      paint,
    );

    // Hastes verticais nas extremidades
    final verticalLength = coordinates.staffSpace * 0.4; // Aumentado de 0.3
    canvas.drawLine(
      Offset(firstNote.dx, bracketY),
      Offset(firstNote.dx, bracketY + verticalLength),
      paint,
    );
    canvas.drawLine(
      Offset(lastNote.dx, bracketY),
      Offset(lastNote.dx, bracketY + verticalLength),
      paint,
    );
  }

  void _drawTupletNumber(
    Canvas canvas,
    List<Offset> notePositions,
    int number,
  ) {
    if (notePositions.isEmpty) return;

    final centerX = (notePositions.first.dx + notePositions.last.dx) / 2;
    // CORREÇÃO: Alinhar com o bracket (tupletNumberDistance = 0.5)
    final numberY = notePositions.first.dy - (coordinates.staffSpace * 3.8);

    final glyphName = 'tuplet$number';

    _drawGlyph(
      canvas,
      glyphName: glyphName,
      position: Offset(centerX, numberY),
      size: glyphSize * 0.7, // CORREÇÃO: Aumentado de 0.6 para melhor legibilidade
      color: theme.stemColor,
      centerVertically: true,
      centerHorizontally: true,
    );
  }

  void _drawGlyph(
    Canvas canvas, {
    required String glyphName,
    required Offset position,
    required double size,
    required Color color,
    bool centerVertically = false,
    bool centerHorizontally = false,
  }) {
    final character = metadata.getCodepoint(glyphName);
    if (character.isEmpty) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: character,
        style: TextStyle(
          fontFamily: 'Bravura',
          fontSize: size,
          color: color,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final yOffset = centerVertically ? -textPainter.height * 0.5 : 0;
    final xOffset = centerHorizontally ? -textPainter.width * 0.5 : 0;

    textPainter.paint(
      canvas,
      Offset(position.dx + xOffset, position.dy + yOffset),
    );
  }
}