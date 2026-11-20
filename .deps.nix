{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "pitches-0.1.0-pcDEyZx6AABD_--oGDHDs6eN9KKZlGo6Hk70knpiQJrg";
    path = fetchzip {
      url = "https://github.com/haruki7049/pitches/archive/ff043817d4baaf54f83044eb6c542319659e4017.tar.gz";
      hash = "sha256-LgPd7CPyQoAWFVsl+Noe7/xtCjEKHbKoIRFitkb/Oi8=";
    };
  }
  {
    name = "lightmix-0.27.0-SpCovFCuBAAAceJzkDPOiufO2_xoVM-KcKyeo4RuAdcR";
    path = fetchzip {
      url = "https://github.com/haruki7049/lightmix/archive/refs/tags/0.27.0.tar.gz";
      hash = "sha256-QvfRKSuoUpPOtDXPD2604E9tzUzj7oUJ+srFGlffVJ8=";
    };
  }
  {
    name = "riff_zig-3.0.0-J7H0A9jpTQAfXyEpqGjgyWGcYkf_dOprHoD3aSDguFoA";
    path = fetchzip {
      url = "https://github.com/haruki7049/RIFF.zig/archive/refs/tags/3.0.0.tar.gz";
      hash = "sha256-i+ie4xBFQOWw2OwcUgcrUp1oZVV7J8uyNyIYQgx6zwM=";
    };
  }
  {
    name = "zigggwavvv-3.0.0-iR5xWnp2AgClpXY_jdEOQvIJBfvYHCGawUuhUtOS0wKZ";
    path = fetchzip {
      url = "https://github.com/haruki7049/zigggwavvv/archive/refs/tags/3.0.0.tar.gz";
      hash = "sha256-Na6XNssRmtzjFbiS9lDZAhlf4Jbla15BgTFNcEuwUB4=";
    };
  }
]
