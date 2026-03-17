// Simple grid-based layout using 16th notes as the base unit.
// 
// In 4/4 time:
//   - Measure width = 16 units (16 sixteenth notes)
//   - Quarter note = 4 units
//   - Half note = 8 units
//   - Whole note = 16 units
//   - Eighth note = 2 units
//   - Dotted quarter = 6 units
//   - etc.
//
// This makes timing alignment trivially correct.

import 'package:flutter_notemus/core/core.dart';
import 'package:flutter_notemus/core/duration.dart' as music;

/// Grid units (1 unit = 1 sixteenth note)
class GridUnits {
  static const double sixteenth = 1;
  static const double eighth = 2;
  static const double dottedEighth = 3;
  static const double quarter = 4;
  static const double dottedQuarter = 6;
  static const double half = 8;
  static const double dottedHalf = 12;
  static const double whole = 16;
  
  // Triplets (3 in the space of 2)
  static const double eighthTriplet = 4 / 3;        // ~1.33 units
  static const double quarterTriplet = 8 / 3;       // ~2.67 units
  
  // Quintuplets (5 in the space of 4) 
  static const double eighthQuintuplet = 8 / 5;     // 1.6 units
  static const double quarterQuintuplet = 16 / 5;   // 3.2 units
  
  // Septuplets (7 in the space of 4)
  static const double eighthSeptuplet = 8 / 7;      // ~1.14 units
  static const double quarterSeptuplet = 16 / 7;    // ~2.29 units
  
  /// Convert a Duration to grid units
  static double fromDuration(music.Duration duration) {
    double baseUnits;
    
    switch (duration.type) {
      case DurationType.whole:
        baseUnits = whole;
        break;
      case DurationType.half:
        baseUnits = half;
        break;
      case DurationType.quarter:
        baseUnits = quarter;
        break;
      case DurationType.eighth:
        baseUnits = eighth;
        break;
      case DurationType.sixteenth:
        baseUnits = sixteenth;
        break;
      case DurationType.thirtySecond:
        baseUnits = 0.5;
        break;
      default:
        baseUnits = quarter;
    }
    
    // Apply dots: each dot adds half of the previous value
    double total = baseUnits;
    double dotValue = baseUnits;
    for (int i = 0; i < duration.dots; i++) {
      dotValue /= 2;
      total += dotValue;
    }
    
    return total;
  }
  
  /// Get units per measure for a time signature
  static double unitsPerMeasure(TimeSignature timeSig) {
    // In 4/4: 4 quarters = 16 units
    // In 3/4: 3 quarters = 12 units
    // In 6/8: 6 eighths = 12 units
    // In 2/2: 2 halfs = 16 units
    
    double unitsPerBeat;
    switch (timeSig.denominator) {
      case 2: unitsPerBeat = half; break;      // Half note = 8 units
      case 4: unitsPerBeat = quarter; break;   // Quarter = 4 units
      case 8: unitsPerBeat = eighth; break;    // Eighth = 2 units
      case 16: unitsPerBeat = sixteenth; break; // 16th = 1 unit
      default: unitsPerBeat = quarter;
    }
    
    return timeSig.numerator * unitsPerBeat;
  }
}

/// A note positioned on the simple grid
class SimpleGridTuplet {
  final double startGrid;
  final double endGrid;
  final int number;
  final int displayNumber;
  final List<SimpleGridNote> notes;

  SimpleGridTuplet({
    required this.startGrid,
    required this.endGrid,
    required this.number,
    required this.displayNumber,
    required this.notes,
  });
}

class SimpleGridNote {
  final MusicalElement element;
  final int measureIndex;
  final double gridPosition;  // Grid units from start of piece
  final double gridDuration;  // Duration in grid units
  final int staffPosition;    // Vertical staff position
  final bool isBass;
  final SimpleGridTuplet? tuplet;
  
  SimpleGridNote({
    required this.element,
    required this.measureIndex,
    required this.gridPosition,
    required this.gridDuration,
    required this.staffPosition,
    this.isBass = false,
    this.tuplet,
  });
}

/// Info about a measure
class SimpleGridMeasure {
  final int index;
  final double startGrid;     // Grid position where measure starts
  final double gridWidth;     // Width in grid units
  final TimeSignature timeSig;
  final List<SimpleGridNote> notes;
  final String? number;
  final List<int> endings;
  final List<RepeatMark> navigationMarks;
  final bool hasStartRepeat;
  final bool hasEndRepeat;
  
  SimpleGridMeasure({
    required this.index,
    required this.startGrid,
    required this.gridWidth,
    required this.timeSig,
    required this.notes,
    this.number,
    this.endings = const [],
    this.navigationMarks = const [],
    this.hasStartRepeat = false,
    this.hasEndRepeat = false,
  });
  
  double get endGrid => startGrid + gridWidth;
}

/// Result of simple grid layout
class SimpleGridLayout {
  final List<SimpleGridMeasure> measures;
  final List<SimpleGridNote> allNotes;
  final double totalGridUnits;
  final bool isBass;
  final List<SimpleGridTuplet> tuplets;
  
  SimpleGridLayout({
    required this.measures,
    required this.allNotes,
    required this.totalGridUnits,
    this.isBass = false,
    this.tuplets = const [],
  });
  
  /// Total beats (for BPM calculations)
  double get totalBeats => totalGridUnits / GridUnits.quarter;
}

/// Simple grid layout calculator
class SimpleGridLayoutEngine {
  final Staff staff;
  final bool isBass;
  
  SimpleGridLayoutEngine({
    required this.staff,
    this.isBass = false,
  });
  
  SimpleGridLayout calculate() {
    final measures = <SimpleGridMeasure>[];
    final allNotes = <SimpleGridNote>[];
    
    double currentGridPos = 0;
    TimeSignature currentTimeSig = TimeSignature(numerator: 4, denominator: 4);
    Clef currentClef = Clef(clefType: isBass ? ClefType.bass : ClefType.treble);
    
    for (int measureIndex = 0; measureIndex < staff.measures.length; measureIndex++) {
      final measure = staff.measures[measureIndex];
      final measureStartGrid = currentGridPos;
      final measureNotes = <SimpleGridNote>[];
      
      // First pass: find time signature and clef
      for (final element in measure.elements) {
        if (element is TimeSignature) {
          currentTimeSig = element;
        } else if (element is Clef) {
          currentClef = element;
        }
      }
      
      final measureGridWidth = GridUnits.unitsPerMeasure(currentTimeSig);
      
      // Second pass: position notes
      double gridInMeasure = 0;
      bool hasStartRepeat = false;
      bool hasEndRepeat = false;

      for (final element in measure.elements) {
        if (element is Barline) {
          if (element.type == BarlineType.repeatForward) {
            hasStartRepeat = true;
          } else if (element.type == BarlineType.repeatBackward) {
            hasEndRepeat = true;
          } else if (element.type == BarlineType.repeatBoth) {
            hasStartRepeat = true;
            hasEndRepeat = true;
          }
        } else if (element is Note) {
          final gridDuration = GridUnits.fromDuration(element.duration);
          final staffPos = _calculateStaffPosition(element.pitch, currentClef);
          
          measureNotes.add(SimpleGridNote(
            element: element,
            measureIndex: measureIndex,
            gridPosition: measureStartGrid + gridInMeasure,
            gridDuration: gridDuration,
            staffPosition: staffPos,
            isBass: currentClef.clefType == ClefType.bass,
          ));
          
          gridInMeasure += gridDuration;
        } else if (element is Rest) {
          final gridDuration = GridUnits.fromDuration(element.duration);
          
          measureNotes.add(SimpleGridNote(
            element: element,
            measureIndex: measureIndex,
            gridPosition: measureStartGrid + gridInMeasure,
            gridDuration: gridDuration,
            staffPosition: 0,
            isBass: currentClef.clefType == ClefType.bass,
          ));
          
          gridInMeasure += gridDuration;
        } else if (element is Chord) {
          final gridDuration = GridUnits.fromDuration(element.duration);
          
          measureNotes.add(SimpleGridNote(
            element: element,
            measureIndex: measureIndex,
            gridPosition: measureStartGrid + gridInMeasure,
            gridDuration: gridDuration,
            staffPosition: 0,
            isBass: currentClef.clefType == ClefType.bass,
          ));
          
          gridInMeasure += gridDuration;
        }
      }
      
      measures.add(SimpleGridMeasure(
        index: measureIndex,
        startGrid: measureStartGrid,
        gridWidth: measureGridWidth,
        timeSig: currentTimeSig,
        notes: measureNotes,
        endings: List<int>.unmodifiable(measure.endings),
        navigationMarks: List<RepeatMark>.unmodifiable(measure.navigationMarks),
        hasStartRepeat: hasStartRepeat || measure.repeatForward,
        hasEndRepeat: hasEndRepeat || measure.repeatBackward,
      ));
      
      allNotes.addAll(measureNotes);
      currentGridPos += measureGridWidth;
    }
    
    return SimpleGridLayout(
      measures: measures,
      allNotes: allNotes,
      totalGridUnits: currentGridPos,
      isBass: isBass,
    );
  }
  
  /// Calculate staff position for a pitch
  int _calculateStaffPosition(Pitch pitch, Clef clef) {
    // Staff position: 0 = middle line (B4 for treble, D3 for bass)
    // Positive = above, negative = below
    // Each step is half a staff space
    
    final steps = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};
    final step = steps[pitch.step] ?? 0;
    
    if (clef.clefType == ClefType.treble) {
      // B4 = 0, so we calculate relative to that
      // B4 = step 6, octave 4
      final referenceValue = 6 + (4 * 7); // B4 = 34
      final noteValue = step + (pitch.octave * 7);
      return noteValue - referenceValue;
    } else {
      // Bass clef: D3 = 0
      // D3 = step 1, octave 3
      final referenceValue = 1 + (3 * 7); // D3 = 22
      final noteValue = step + (pitch.octave * 7);
      return noteValue - referenceValue;
    }
  }
}

/// Combined layout for grand staff
class SimpleGrandStaffLayout {
  final SimpleGridLayout treble;
  final SimpleGridLayout? bass;
  
  SimpleGrandStaffLayout({
    required this.treble,
    this.bass,
  });
  
  double get totalGridUnits {
    if (bass == null) return treble.totalGridUnits;
    return treble.totalGridUnits > bass!.totalGridUnits 
        ? treble.totalGridUnits 
        : bass!.totalGridUnits;
  }
  
  double get totalBeats => totalGridUnits / GridUnits.quarter;
  
  int get measureCount => treble.measures.length;
}