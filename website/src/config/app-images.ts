const responsiveImage = (name: string) => ({
  src: `/images/app/${name}.webp`,
  srcset: [
    `/images/app/${name}-960.webp 960w`,
    `/images/app/${name}-1600.webp 1600w`,
    `/images/app/${name}.webp 2774w`,
  ].join(", "),
});

export const appImages = {
  canales: responsiveImage("estrobo-canales"),
  conexion: responsiveImage("estrobo-conexion"),
  inspector: responsiveImage("estrobo-inspector"),
  matriz: responsiveImage("estrobo-matriz"),
  primerInicio: responsiveImage("estrobo-primer-inicio"),
} as const;
