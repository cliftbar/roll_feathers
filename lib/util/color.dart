import 'package:flutter/material.dart';

final colorMap = {
  // primary led
  'blue': Color.fromARGB(255, 0, 0, 255),
  'green': Color.fromARGB(255, 0, 255, 0),
  'red': Color.fromARGB(255, 255, 0, 0),
  'orange': Color.fromARGB(255, 255, 128, 0),
  'magenta': Color.fromARGB(255, 255, 0, 255),
  'purple': Color.fromARGB(255, 128, 0, 255),
  'cyan': Color.fromARGB(255, 0, 255, 255),
  'pink': Color.fromARGB(255, 255, 0, 128),
  'yellow': Color.fromARGB(255, 255, 255, 0),
  'indigo': Color.fromARGB(255, 75, 0, 130),
  'violet': Color.fromARGB(255, 127, 0, 255),
  // catan
  "brick": Color.fromARGB(255, 255, 0, 29),
  "hills": Color.fromARGB(255, 255, 0, 29),
  "wheat": Color.fromARGB(255, 255, 200, 0),
  "grain": Color.fromARGB(255, 255, 200, 0),
  "field": Color.fromARGB(255, 255, 200, 0),
  "wood": Color.fromARGB(255, 7, 71, 0),
  "lumber": Color.fromARGB(255, 7, 71, 0),
  "forest": Color.fromARGB(255, 7, 71, 0),
  "ore": Color.fromARGB(255, 137, 197, 255),
  "stone": Color.fromARGB(255, 137, 197, 255),
  "mountain": Color.fromARGB(255, 137, 197, 255),
  "sheep": Color.fromARGB(255, 138, 255, 0),
  "pasture": Color.fromARGB(255, 138, 255, 0),

  // material
  'black': Colors.black,
  'amber': Colors.amber,
  'brown': Colors.brown,
  'deepOrange': Colors.deepOrange,
  'deepPurple': Colors.deepPurple,
  'grey': Colors.grey,

  'lightBlue': Colors.lightBlue,
  'lightGreen': Colors.lightGreen,
  'lime': Colors.lime,
  'teal': Colors.teal,
  'white': Colors.white,
  'blueGrey': Colors.blueGrey,
  'transparent': Colors.transparent,
  'redAccent': Colors.redAccent,
  'pinkAccent': Colors.pinkAccent,
  'purpleAccent': Colors.purpleAccent,
  'deepPurpleAccent': Colors.deepPurpleAccent,
  'indigoAccent': Colors.indigoAccent,
  'blueAccent': Colors.blueAccent,
  'lightBlueAccent': Colors.lightBlueAccent,
  'cyanAccent': Colors.cyanAccent,
  'tealAccent': Colors.tealAccent,
  'greenAccent': Colors.greenAccent,
  'lightGreenAccent': Colors.lightGreenAccent,
  'limeAccent': Colors.limeAccent,
  'yellowAccent': Colors.yellowAccent,
  'amberAccent': Colors.amberAccent,
  'orangeAccent': Colors.orangeAccent,
  'deepOrangeAccent': Colors.deepOrangeAccent,
};

mixin Color255 {
  Color getColor();

  int r255() {
    return (getColor().r * getColor().a * 255).toInt();
  }

  int g255() {
    return (getColor().g * getColor().a * 255).toInt();
  }

  int b255() {
    return (getColor().b * getColor().a * 255).toInt();
  }

  int a255() {
    return (getColor().a * 255).toInt();
  }
}

class RFColor extends Color with Color255 {
  RFColor(super.value);

  static RFColor of(Color c) {
    return RFColor(c.toARGB32());
  }

  @override
  Color getColor() {
    return this;
  }
}
