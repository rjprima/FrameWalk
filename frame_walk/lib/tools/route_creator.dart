import 'package:xml/xml.dart';
import 'dart:io';

void main(List<String> arguments) async {
  final f = File(arguments[0]);
  final xmlString = await f.readAsString();
  final document = XmlDocument.parse(xmlString);
}