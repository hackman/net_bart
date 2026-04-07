use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Net::BART::XS',
    VERSION_FROM => 'XS.pm',
    XS           => { 'XS.xs' => 'XS.c' },
    OBJECT       => 'XS$(OBJ_EXT)',
    INC          => '-I.',
    OPTIMIZE     => '-O2',
    clean        => { FILES => 'XS.c' },
);
