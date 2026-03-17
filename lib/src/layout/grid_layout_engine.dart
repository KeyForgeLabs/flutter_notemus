// Grid-based layout engine for sight reading / performance mode.
// Uses a fixed grid where note positions are determined purely by their
// rhythmic duration, ensuring perfect playhead alignment.
//
// Base unit: 840 ticks per quarter note (LCM of 2, 3, 5, 7)
// This allows clean integer math for all common subdivisions including triplets,
// quintuplets, and septuplets.

import 'package:flutter/material.dart';
import 'package:flutter_notemus/core/core.dart';
import 'package:flutter_notemus/core/duration.dart' as music;
import 'package:flutter_notemus/src/rendering/staff_position_calculator.dart';

/// Ticks per quarter note - chosen as LCM(2,3,5,7) × base for clean math
const int ticksPerQuarter = 840;

/// Duration values in ticks
class GridDuration {
  // Standard durations
  static const int whole = ticksPerQuarter * 4;           // 3360
  static const int half = ticksPerQuarter * 2;            // 1680
  static const int quarter = ticksPerQuarter;             // 840
  static const int eighth = ticksPerQuarter ~/ 2;         // 420
  static const int sixteenth = ticksPerQuarter ~/ 4;      // 210
  static const int thirtySecond = ticksPerQuarter ~/ 8;   // 105
  
  // Triplets (3 in the space of 2)
  static const int halfTriplet = half * 2 ~/ 3;           // 1120 (3 in space of 2 halves = 1 whole)
  static const int quarterTriplet = quarter * 2 ~/ 3;     // 560 (3 in space of 2 quarters = 1 half)
  static const int eighthTriplet = eighth * 2 ~/ 3;       // 280 (3 in space of 2 eighths = 1 quarter)
  static const int sixteenthTriplet = sixteenth * 2 ~/ 3; // 140 (3 in space of 2 16ths = 1 eighth)
  
  // Quintuplets (5 in the space of 4)
  static const int quarterQuintuplet = quarter * 4 ~/ 5;  // 672 (5 in space of 4 quarters = 1 whole)
  static const int eighthQuintuplet = eighth * 4 ~/ 5;    // 336 (5 in space of 4 eighths = 1 half)
  static const int sixteenthQuintuplet = sixteenth * 4 ~/ 5; // 168 (5 in space of 4 16ths = 1 quarter)
  
  // Septuplets (7 in the space of 4)
  static const int quarterSeptuplet = quarter * 4 ~/ 7;   // 480 (7 in space of 4 quarters = 1 whole)
  static const int eighthSeptuplet = eighth * 4 ~/ 7;     // 240 (7 in space of 4 eighths = 1 half)
  static const int sixteenthSeptuplet = sixteenth * 4 ~/ 7; // 120 (7 in space of 4 16ths = 1 quarter)
  
  /// Convert a Duration to ticks
  static int fromDuration(music.Duration duration) {
    int baseTicks;
    
    switch (duration.type) {
      case DurationType.whole:
        baseTicks = whole;
        break;
      case DurationType.half:
        baseTicks = half;
        break;
      case DurationType.quarter:
        baseTicks = quarter;
        break;
      case DurationType.eighth:
        baseTicks = eighth;
        break;
      case DurationType.sixteenth:
        baseTicks = sixteenth;
        break;
      case DurationType.thirtySecond:
        baseTicks = thirtySecond;
        break;
      default:
        baseTicks = quarter; // Fallback
    }
    
    // Apply dots: each dot adds half of the previous value
    double totalTicks = baseTicks.toDouble();
    double dotValue = baseTicks.toDouble();
    for (int i = 0; i < duration.dots; i++) {
      dotValue /= 2;
      totalTicks += dotValue;
    }
    
    return totalTicks.round();
  }
  
  /// Convert ticks to beats (for BPM calculations)
  static double ticksToBeats(int ticks) => ticks / ticksPerQuarter;
  
  /// Convert beats to ticks
  static int beatsToTicks(double beats) => (beats * ticksPerQuarter).round();
}

/// A note positioned on the grid
class GridPositionedNote {
  final MusicalElement element;
  final int measureIndex;
  final int tickPosition;      // Absolute tick position from start
  final int tickDuration;      // Duration in ticks
  final int staffPosition;     // Vertical staff position
  final bool isBassClef;
  
  GridPositionedNote({
    required this.element,
    required this.measureIndex,
    required this.tickPosition,
    required this.tickDuration,
    required this.staffPosition,
    this.isBassClef = false,
  });
  
  /// X position in pixels given pixels per tick
  double xPosition(double pixelsPerTick) => tickPosition * pixelsPerTick;
  
  /// Beat position (for display)
  double get beatPosition => GridDuration.ticksToBeats(tickPosition);
}

/// Layout info for a single measure
class GridMeasureInfo {
  final int measureIndex;
  final int startTick;
  final int endTick;
  final int ticksPerMeasure;
  final TimeSignature timeSignature;
  final List<GridPositionedNote> notes;
  
  GridMeasureInfo({
    required this.measureIndex,
    required this.startTick,
    required this.endTick,
    required this.ticksPerMeasure,
    required this.timeSignature,
    required this.notes,
  });
  
  int get durationTicks => endTick - startTick;
}

/// Result of grid layout calculation
class GridLayoutResult {
  final List<GridMeasureInfo> measures;
  final List<GridPositionedNote> allNotes;
  final int totalTicks;
  final double totalBeats;
  
  /// Width of system elements (clef, key sig, time sig) at the start
  final double systemElementsWidth;
  
  GridLayoutResult({
    required this.measures,
    required this.allNotes,
    required this.totalTicks,
    required this.systemElementsWidth,
  }) : totalBeats = GridDuration.ticksToBeats(totalTicks);
  
  /// Calculate total width given pixels per tick and staff space
  double totalWidth(double pixelsPerTick) => 
      systemElementsWidth + (totalTicks * pixelsPerTick);
}

/// Grid-based layout engine for perfect timing alignment
class GridLayoutEngine {
  final Staff staff;
  final double staffSpace;
  final bool isBassClef;
  
  GridLayoutEngine({
    required this.staff,
    required this.staffSpace,
    this.isBassClef = false,
  });
  
  /// Calculate grid layout for the staff
  GridLayoutResult calculate() {
    final measures = <GridMeasureInfo>[];
    final allNotes = <GridPositionedNote>[];
    
    int currentTick = 0;
    TimeSignature currentTimeSig = TimeSignature(numerator: 4, denominator: 4);
    Clef currentClef = Clef(clefType: isBassClef ? ClefType.bass : ClefType.treble);
    
    // Calculate system elements width (clef + key sig + time sig)
    // Approximate: clef ~2 spaces, key sig ~0-3 spaces, time sig ~2 spaces, padding ~1 space
    double systemElementsWidth = staffSpace * 5; // Conservative estimate
    
    for (int measureIndex = 0; measureIndex < staff.measures.length; measureIndex++) {
      final measure = staff.measures[measureIndex];
      final measureStartTick = currentTick;
      final measureNotes = <GridPositionedNote>[];
      
      // First pass: find time signature and clef
      for (final element in measure.elements) {
        if (element is TimeSignature) {
          currentTimeSig = element;
        } else if (element is Clef) {
          currentClef = element;
        }
      }
      
      // Calculate ticks per measure based on time signature
      // numerator = beats per measure, denominator = beat unit
      // For 4/4: 4 quarter notes = 4 * 840 = 3360 ticks
      // For 6/8: 6 eighth notes = 6 * 420 = 2520 ticks
      final ticksPerBeatUnit = _ticksForBeatUnit(currentTimeSig.denominator);
      final ticksPerMeasure = currentTimeSig.numerator * ticksPerBeatUnit;
      
      // Second pass: position notes
      int tickInMeasure = 0;
      for (final element in measure.elements) {
        if (element is Note) {
          final tickDuration = GridDuration.fromDuration(element.duration);
          final staffPos = StaffPositionCalculator.calculate(element.pitch, currentClef);
          
          measureNotes.add(GridPositionedNote(
            element: element,
            measureIndex: measureIndex,
            tickPosition: measureStartTick + tickInMeasure,
            tickDuration: tickDuration,
            staffPosition: staffPos,
            isBassClef: currentClef.clefType == ClefType.bass,
          ));
          
          tickInMeasure += tickDuration;
        } else if (element is Rest) {
          final tickDuration = GridDuration.fromDuration(element.duration);
          
          measureNotes.add(GridPositionedNote(
            element: element,
            measureIndex: measureIndex,
            tickPosition: measureStartTick + tickInMeasure,
            tickDuration: tickDuration,
            staffPosition: 0, // Rests don't have staff position
            isBassClef: currentClef.clefType == ClefType.bass,
          ));
          
          tickInMeasure += tickDuration;
        } else if (element is Chord) {
          final tickDuration = GridDuration.fromDuration(element.duration);
          
          // For chords, we add one entry but could expand to individual notes
          measureNotes.add(GridPositionedNote(
            element: element,
            measureIndex: measureIndex,
            tickPosition: measureStartTick + tickInMeasure,
            tickDuration: tickDuration,
            staffPosition: 0, // Chord position handled separately
            isBassClef: currentClef.clefType == ClefType.bass,
          ));
          
          tickInMeasure += tickDuration;
        }
      }
      
      // Use actual content duration or measure duration, whichever is greater
      final measureEndTick = measureStartTick + 
          (tickInMeasure > ticksPerMeasure ? tickInMeasure : ticksPerMeasure);
      
      measures.add(GridMeasureInfo(
        measureIndex: measureIndex,
        startTick: measureStartTick,
        endTick: measureEndTick,
        ticksPerMeasure: ticksPerMeasure,
        timeSignature: currentTimeSig,
        notes: measureNotes,
      ));
      
      allNotes.addAll(measureNotes);
      currentTick = measureEndTick;
    }
    
    return GridLayoutResult(
      measures: measures,
      allNotes: allNotes,
      totalTicks: currentTick,
      systemElementsWidth: systemElementsWidth,
    );
  }
  
  /// Get ticks for a beat unit denominator
  int _ticksForBeatUnit(int denominator) {
    switch (denominator) {
      case 1: return GridDuration.whole;
      case 2: return GridDuration.half;
      case 4: return GridDuration.quarter;
      case 8: return GridDuration.eighth;
      case 16: return GridDuration.sixteenth;
      case 32: return GridDuration.thirtySecond;
      default: return GridDuration.quarter;
    }
  }
}

/// Utility to calculate combined grid layout for grand staff
class GrandStaffGridLayout {
  final GridLayoutResult trebleLayout;
  final GridLayoutResult? bassLayout;
  
  GrandStaffGridLayout({
    required this.trebleLayout,
    this.bassLayout,
  });
  
  /// Total ticks (max of both staves)
  int get totalTicks {
    if (bassLayout == null) return trebleLayout.totalTicks;
    return trebleLayout.totalTicks > bassLayout!.totalTicks 
        ? trebleLayout.totalTicks 
        : bassLayout!.totalTicks;
  }
  
  /// Total beats
  double get totalBeats => GridDuration.ticksToBeats(totalTicks);
  
  /// System elements width (max of both staves)
  double get systemElementsWidth {
    if (bassLayout == null) return trebleLayout.systemElementsWidth;
    return trebleLayout.systemElementsWidth > bassLayout!.systemElementsWidth
        ? trebleLayout.systemElementsWidth
        : bassLayout!.systemElementsWidth;
  }
  
  /// Calculate total width
  double totalWidth(double pixelsPerTick) => 
      systemElementsWidth + (totalTicks * pixelsPerTick);
  
  /// Get all notes from both staves, sorted by tick position
  List<GridPositionedNote> get allNotes {
    final notes = [...trebleLayout.allNotes];
    if (bassLayout != null) {
      notes.addAll(bassLayout!.allNotes);
    }
    notes.sort((a, b) => a.tickPosition.compareTo(b.tickPosition));
    return notes;
  }
}