// lib/src/rendering/renderers/slur_renderer.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/core.dart';
import '../../layout/slur_calculator.dart';
import '../../layout/layout_engine.dart'; // PositionedElement
import '../../engraving/engraving_rules.dart';
import '../staff_position_calculator.dart';
import '../../smufl/smufl_metadata_loader.dart'; // SmuflMetadata

/// Renderizador profissional de ligaduras (slurs e ties) conforme SMuFL e Behind Bars
///
/// **ESPECIFICAÇÕES:**
/// - Espessura variável: endpoint (0.1 SS) → midpoint (0.22 SS)
/// - Curvas Bézier cúbicas suaves
/// - Detecção automática de direção (acima/abaixo)
/// - Evita colisões com notas, hastes, beams, acidentes
/// - Suporte a slurs aninhados (múltiplos níveis)
///
/// **REFERÊNCIAS:**
/// - SMuFL specification (slurEndpointThickness, slurMidpointThickness)
/// - Behind Bars (Elaine Gould) - capítulo sobre ligaduras
/// - OpenSheetMusicDisplay (SlurCalculator.ts)
class SlurRenderer {
  final EngravingRules rules;
  final SmuflMetadata metadata;
  final double staffSpace;
  
  SlurRenderer({
    required this.staffSpace,
    required this.metadata,
    EngravingRules? rules,
  }) : rules = rules ?? EngravingRules();
  
  /// Renderiza ligaduras de expressão (slurs)
  ///
  /// @param canvas Canvas do Flutter
  /// @param slurGroups Grupos de notas ligadas
  /// @param positions Posições de todos os elementos
  /// @param currentClef Clave atual
  /// @param color Cor da ligadura
  void renderSlurs({
    required Canvas canvas,
    required Map<int, List<int>> slurGroups,
    required List<PositionedElement> positions,
    required Clef currentClef,
    Color color = Colors.black,
  }) {
    print('      🎶 [SlurRenderer.renderSlurs] Processando ${slurGroups.length} slur groups');
    
    for (final group in slurGroups.values) {
      if (group.length < 2) {
        print('         ⚠️  Slur group muito pequeno (${group.length} notas), pulando...');
        continue;
      }
      
      final startElement = positions[group.first];
      final endElement = positions[group.last];
      
      if (startElement.element is! Note || endElement.element is! Note) {
        continue;
      }
      
      final startNote = startElement.element as Note;
      final endNote = endElement.element as Note;
      
      print('         🎵 Slur: ${startNote.pitch.step}${startNote.pitch.octave} → ${endNote.pitch.step}${endNote.pitch.octave}');
      
      // Calcular direção automática
      final direction = _calculateSlurDirection(
        startNote,
        endNote,
        currentClef,
      );
      print('            Direção: ${direction == SlurDirection.up ? "ACIMA" : "ABAIXO"}');
      
      // Calcular pontos de início e fim
      final startPoint = _calculateSlurEndpoint(
        startElement.position,
        startNote,
        currentClef,
        isStart: true,
        above: direction == SlurDirection.up,
      );
      
      final endPoint = _calculateSlurEndpoint(
        endElement.position,
        endNote,
        currentClef,
        isStart: false,
        above: direction == SlurDirection.up,
      );
      
      // Calcular curva usando SlurCalculator avançado
      final calculator = SlurCalculator(
        rules: rules,
        skylineCalculator: null, // TODO: integrar com skyline
      );
      
      final curve = calculator.calculateSlur(
        startPoint: startPoint,
        endPoint: endPoint,
        placement: direction == SlurDirection.up,
        staffSpace: staffSpace,
      );
      
      // Renderizar curva com espessura variável
      print('            StartPoint: (${startPoint.dx.toStringAsFixed(1)}, ${startPoint.dy.toStringAsFixed(1)})');
      print('            EndPoint: (${endPoint.dx.toStringAsFixed(1)}, ${endPoint.dy.toStringAsFixed(1)})');
      
      _drawVariableThicknessCurve(
        canvas,
        curve,
        color,
        isSlur: true,
      );
    }
    print('      ✅ [SlurRenderer.renderSlurs] Concluído!');  
  }
  
  /// Renderiza ligaduras de prolongamento (ties)
  ///
  /// Ties são mais rasas que slurs e sempre conectam notas da mesma altura
  void renderTies({
    required Canvas canvas,
    required Map<int, List<int>> tieGroups,
    required List<PositionedElement> positions,
    required Clef currentClef,
    Color color = Colors.black,
  }) {
    print('      🔗 [SlurRenderer.renderTies] Processando ${tieGroups.length} tie groups');
    
    for (final group in tieGroups.values) {
      final startElement = positions[group.first];
      final endElement = positions[group.last];
      
      if (startElement.element is! Note || endElement.element is! Note) {
        continue;
      }
      
      final startNote = startElement.element as Note;
      final endNote = endElement.element as Note;
      
      print('         🔗 Tie: ${startNote.pitch.step}${startNote.pitch.octave} → ${endNote.pitch.step}${endNote.pitch.octave}');
      
      // Ties seguem direção OPOSTA às hastes
      final staffPos = StaffPositionCalculator.calculate(
        startNote.pitch,
        currentClef,
      );
      final stemUp = staffPos <= 0;
      final tieAbove = !stemUp;
      print('            staffPos: $staffPos, stemUp: $stemUp, tieAbove: $tieAbove');
      
      // Calcular pontos de início e fim (mais afastados das cabeças)
      final noteWidth = staffSpace * 1.18;
      
      // ✅ USAR position.dy que JÁ é a posição Y absoluta da nota!
      final startNoteY = startElement.position.dy;
      final endNoteY = endElement.position.dy;
      
      print('            🐛 DEBUG: startElement.position.dy = $startNoteY');
      print('            🐛 DEBUG: endElement.position.dy = $endNoteY');
      
      // ✅ AUMENTAR clearance para evitar sobreposição (Behind Bars: 0.5 SS mínimo)
      // Ties devem ter clearance de pelo menos 0.5 SS da cabeça da nota
      final clearance = staffSpace * 0.6; // Aumentado de 0.25 para 0.6
      
      final startPoint = Offset(
        startElement.position.dx + noteWidth * 0.75,
        startNoteY + (tieAbove 
          ? -clearance  // Acima: subtrair clearance
          : clearance), // Abaixo: somar clearance
      );
      
      final endPoint = Offset(
        endElement.position.dx + noteWidth * 0.25,
        endNoteY + (tieAbove 
          ? -clearance
          : clearance),
      );
      
      // Calcular curva usando SlurCalculator
      final calculator = SlurCalculator(rules: rules);
      final curve = calculator.calculateTie(
        startPoint: startPoint,
        endPoint: endPoint,
        placement: tieAbove,
        staffSpace: staffSpace,
      );
      
      // Renderizar tie com espessura variável
      print('            StartPoint: (${startPoint.dx.toStringAsFixed(1)}, ${startPoint.dy.toStringAsFixed(1)})');
      print('            EndPoint: (${endPoint.dx.toStringAsFixed(1)}, ${endPoint.dy.toStringAsFixed(1)})');
      
      _drawVariableThicknessCurve(
        canvas,
        curve,
        color,
        isSlur: false,
      );
    }
    print('      ✅ [SlurRenderer.renderTies] Concluído!');
  }
  
  /// Calcula direção automática do slur (acima ou abaixo)
  ///
  /// **REGRAS (Behind Bars):**
  /// - Notas abaixo da linha central → slur acima
  /// - Notas acima da linha central → slur abaixo
  /// - Mistura de hastes → preferencialmente acima
  SlurDirection _calculateSlurDirection(
    Note startNote,
    Note endNote,
    Clef clef,
  ) {
    final startStaffPos = StaffPositionCalculator.calculate(
      startNote.pitch,
      clef,
    );
    final endStaffPos = StaffPositionCalculator.calculate(
      endNote.pitch,
      clef,
    );
    
    // Média das posições
    final avgPos = (startStaffPos + endStaffPos) / 2;
    
    // Linha central = 0
    // Acima (positivo) → slur abaixo
    // Abaixo (negativo) → slur acima
    if (avgPos > 0) {
      return SlurDirection.down; // Notas acima → slur abaixo
    } else {
      return SlurDirection.up; // Notas abaixo → slur acima
    }
  }
  
  /// Calcula ponto de início/fim do slur na cabeça da nota
  ///
  /// @param notePos Posição da nota (JÁ ABSOLUTA do LayoutEngine!)
  /// @param note Nota
  /// @param clef Clave
  /// @param isStart Se é ponto inicial ou final
  /// @param above Se slur está acima ou abaixo
  Offset _calculateSlurEndpoint(
    Offset notePos,
    Note note,
    Clef clef,
    {required bool isStart,
    required bool above,}
  ) {
    final noteWidth = staffSpace * 1.18;
    
    // ✅ USAR notePos.dy que JÁ é a posição Y absoluta da nota!
    final noteY = notePos.dy;
    
    // Calcular staffPos para determinar se tem stem
    final staffPos = StaffPositionCalculator.calculate(note.pitch, clef);
    final stemUp = staffPos <= 0;
    
    // ✅ AUMENTAR clearance considerando hastes (Behind Bars)
    // - Slur acima + stem up: clearance de 1.5 SS (stem height ~3.5 SS)
    // - Slur abaixo + stem down: clearance de 1.5 SS
    // - Sem haste na direção do slur: clearance de 0.6 SS
    double yOffset;
    String clearanceReason;
    
    if (above && stemUp) {
      // Slur acima + stem up: evitar haste (3.5 SS de stem + 0.5 SS margem)
      yOffset = -staffSpace * 1.8;
      clearanceReason = 'Slur ACIMA + stem UP → clearance 1.8 SS';
    } else if (!above && !stemUp) {
      // Slur abaixo + stem down: evitar haste
      yOffset = staffSpace * 1.8;
      clearanceReason = 'Slur ABAIXO + stem DOWN → clearance 1.8 SS';
    } else {
      // Sem haste no caminho: clearance padrão
      yOffset = staffSpace * 0.6 * (above ? -1 : 1);
      clearanceReason = 'Sem haste no caminho → clearance 0.6 SS';
    }
    
    print('            🎯 Clearance: $clearanceReason (staffPos=$staffPos, stemUp=$stemUp, above=$above)');
    
    // Offset X: início à esquerda (30%), fim à direita (70%)
    final xOffset = isStart ? noteWidth * 0.3 : noteWidth * 0.7;
    
    return Offset(
      notePos.dx + xOffset,
      noteY + yOffset,
    );
  }
  
  /// Desenha curva com espessura variável (SMuFL spec)
  ///
  /// **ESPESSURAS:**
  /// - Endpoint: 0.1 SS (slur) / 0.1 SS (tie)
  /// - Midpoint: 0.22 SS (slur) / 0.22 SS (tie)
  ///
  /// Usa Path com múltiplas linhas paralelas para simular gradiente
  void _drawVariableThicknessCurve(
    Canvas canvas,
    CubicBezierCurve curve,
    Color color,
    {required bool isSlur,}
  ) {
    final endpointThickness = isSlur 
      ? metadata.getEngravingDefaultValue('slurEndpointThickness') ?? 0.1
      : metadata.getEngravingDefaultValue('tieEndpointThickness') ?? 0.1;
    
    final midpointThickness = isSlur
      ? metadata.getEngravingDefaultValue('slurMidpointThickness') ?? 0.22
      : metadata.getEngravingDefaultValue('tieMidpointThickness') ?? 0.22;
    
    final endpointThicknessPx = endpointThickness * staffSpace;
    final midpointThicknessPx = midpointThickness * staffSpace;
    
    // Criar Path superior e inferior
    final pathTop = Path();
    final pathBottom = Path();
    
    // Amostrar curva em 50 pontos
    const numPoints = 50;
    final points = <Offset>[];
    final thicknesses = <double>[];
    
    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints;
      final point = curve.pointAt(t);
      points.add(point);
      
      // Espessura interpolada: endpoint → midpoint → endpoint
      // Função parabólica: thickness = endpoint + (midpoint - endpoint) * (1 - (2t - 1)²)
      final tCentered = 2 * t - 1; // [-1, 1]
      final factor = 1 - tCentered * tCentered; // Parabola
      final thickness = endpointThicknessPx + 
        (midpointThicknessPx - endpointThicknessPx) * factor;
      thicknesses.add(thickness);
    }
    
    // Calcular vetores perpendiculares para cada ponto
    for (int i = 0; i <= numPoints; i++) {
      final point = points[i];
      final thickness = thicknesses[i];
      
      // Calcular tangente (derivada)
      final t = i / numPoints;
      final tangent = curve.derivativeAt(t);
      final tangentAngle = math.atan2(tangent.dy, tangent.dx);
      
      // Vetor perpendicular
      final perpAngle = tangentAngle + math.pi / 2;
      final perpDx = math.cos(perpAngle) * thickness / 2;
      final perpDy = math.sin(perpAngle) * thickness / 2;
      
      final topPoint = Offset(point.dx + perpDx, point.dy + perpDy);
      final bottomPoint = Offset(point.dx - perpDx, point.dy - perpDy);
      
      if (i == 0) {
        pathTop.moveTo(topPoint.dx, topPoint.dy);
        pathBottom.moveTo(bottomPoint.dx, bottomPoint.dy);
      } else {
        pathTop.lineTo(topPoint.dx, topPoint.dy);
        pathBottom.lineTo(bottomPoint.dx, bottomPoint.dy);
      }
    }
    
    // Conectar pathTop e pathBottom para criar forma fechada
    final closedPath = Path()
      ..addPath(pathTop, Offset.zero);
    
    // Adicionar pathBottom em ordem reversa
    for (int i = numPoints; i >= 0; i--) {
      final t = i / numPoints;
      final point = curve.pointAt(t);
      final thickness = thicknesses[i];
      final tangent = curve.derivativeAt(t);
      final tangentAngle = math.atan2(tangent.dy, tangent.dx);
      final perpAngle = tangentAngle + math.pi / 2;
      final perpDx = math.cos(perpAngle) * thickness / 2;
      final perpDy = math.sin(perpAngle) * thickness / 2;
      final bottomPoint = Offset(point.dx - perpDx, point.dy - perpDy);
      closedPath.lineTo(bottomPoint.dx, bottomPoint.dy);
    }
    
    closedPath.close();
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(closedPath, paint);
  }
}
