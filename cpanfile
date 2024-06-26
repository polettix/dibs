requires 'perl',            '5.024001';
requires 'Log::Any',        '1.706';
requires 'YAML::XS',        '0.72';
requires 'Path::Tiny',      '0.104';
requires 'Moo',             '2.003004';
requires 'URI',             '1.74';
requires 'Ouch',            '0.0500';
requires 'IPC::Run',        '20180523.0';
requires 'File::chdir',     '0.1010';
requires 'Try::Catch',      '1.1.0';
requires 'Module::Runtime', '0.016';
requires 'Guard',           '1.023';
requires 'HTTP::Tiny',      '0.076';
requires 'IO::Socket::SSL', '1.56';
requires 'Net::SSLeay',     '1.49';
requires 'Pod::Find';

on test => sub {
   requires 'Test2::Suite',    '0.000115';
   requires 'Test::Exception', '0.43';
};
