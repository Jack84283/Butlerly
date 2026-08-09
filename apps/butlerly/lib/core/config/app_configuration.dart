class AppConfiguration {
  const AppConfiguration({this.environment = 'local'});

  final String environment;

  bool get isLocal => environment == 'local';
}
