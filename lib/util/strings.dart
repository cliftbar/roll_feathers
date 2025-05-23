String presentOrElse(String? str, String orElse) {
  if (str?.isEmpty ?? true) {
    return orElse;
  }
  return str!;
}
