{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "meters-0.1.0-EsVLmztkAQCiAyU2pe8rTEO5jTc_KUC9CJTpq3GtkejB";
    path = fetchzip {
      url = "https://github.com/haruki7049/meters/archive/b75cf3cd0078e0b2dac4a1ea95fe4e41aaf0655a.tar.gz";
      hash = "sha256-RBApNgLA0W34UWyO9iwnvjJg5uCtSW+mRdQn8A4F8jg=";
    };
  }
  {
    name = "pitches-0.1.0-pcDEyZx6AABD_--oGDHDs6eN9KKZlGo6Hk70knpiQJrg";
    path = fetchzip {
      url = "https://github.com/haruki7049/pitches/archive/ff043817d4baaf54f83044eb6c542319659e4017.tar.gz";
      hash = "sha256-LgPd7CPyQoAWFVsl+Noe7/xtCjEKHbKoIRFitkb/Oi8=";
    };
  }
  {
    name = "lightmix-0.26.0-SpCovCZcBQBv6Mc5F-Jb99lcspkm-5Bo3m3nowSHKoW3";
    path = fetchzip {
      url = "https://github.com/haruki7049/lightmix/archive/refs/tags/0.26.0.tar.gz";
      hash = "sha256-zB4JTv8x9ODVK4ANEDpq0lDthNhOH6Z+y4ww/bQT9Yg=";
    };
  }
  {
    name = "riff_zig-2.0.0-J7H0A9npTQCZnbwyGH2Ue8AJHRQbEU1T6Ijio7rRdoRN";
    path = fetchzip {
      url = "https://github.com/haruki7049/RIFF.zig/archive/refs/tags/2.0.0.tar.gz";
      hash = "sha256-+Dl0rbYtQsyUHPACEu6duuiBQRvgD9k2VvLIPe4pvko=";
    };
  }
  {
    name = "zigggwavvv-2.0.0-iR5xWutnAgCm4osN3wN-ooN5SNj62hGCBM6yMC4EzRMc";
    path = fetchzip {
      url = "https://github.com/haruki7049/zigggwavvv/archive/refs/tags/2.0.0.tar.gz";
      hash = "sha256-nvCfAWEqgy57+o/z41DGjwFzcYWVbmjbfoLtLyutQew=";
    };
  }
]
