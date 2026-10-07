// Split_cellSens_tiles.ijm
// Splits a cellSens export into separate tile files. Untested in Fiji, so try it on a small file first.
//
// Mode 1 "Grid split": the input is ONE big stitched image (TIFF/PNG/etc.).
//   It is cut into a regular grid of tileW x tileH pixels (optional overlap).
//   Each tile is named by position, e.g. name_1A.tif (top-left = 1A).
//   A TileConfiguration.txt with each tile's pixel position is also written,
//   so the tiles can be re-stitched (Plugins > Stitching > Grid/Collection stitching,
//   "Positions from file").
//   Optionally a <name>_tile_key image is saved: a copy of the original with
//   the tile grid and each tile's label drawn on it.
//   With overlap = 0 and a tile size that divides the image exactly, the tiles
//   reassemble into the original image pixel for pixel.
// Mode 2 "Export all series": the input is a VSI (or other multi-series file).
//   Every series is opened with Bio-Formats and saved as its own file.
//   Series smaller than minSize pixels (labels, thumbnails) are skipped.

#@ File (label="Input image", style="file") inputFile
#@ File (label="Output folder", style="directory") outDir
#@ String (label="Mode", choices={"Grid split (stitched mosaic)","Export all series (VSI / multi-series)"}) mode
#@ Integer (label="Grid: tile width (px)", value=2048) tileW
#@ Integer (label="Grid: tile height (px)", value=1536) tileH
#@ Integer (label="Grid: overlap (px)", value=0) overlap
#@ String (label="Grid: naming", choices={"Row number + column letter (1A, 1B, 2A)","Row letter + column number (A1, A2, B1)"}) naming
#@ Boolean (label="Grid: also save tile key image", value=true) makeKey
#@ Integer (label="Series: skip if width below (px)", value=256) minSize
#@ String (label="Save as", choices={"Tiff","PNG"}) fmt

// 0 -> A, 1 -> B, ... 25 -> Z, 26 -> AA, ...
function colLetters(n) {
    s = "";
    n = n + 1;
    while (n > 0) {
        r = (n - 1) % 26;
        s = fromCharCode(65 + r) + s;
        n = floor((n - 1) / 26);
    }
    return s;
}

setBatchMode(true);
outDir = outDir + File.separator;
name = File.getName(inputFile);
dot = lastIndexOf(name, ".");
if (dot > 0) base = substring(name, 0, dot); else base = name;
ext = ".tif";
if (fmt == "PNG") ext = ".png";

if (startsWith(mode, "Grid")) {
    // ---------- Mode 1: cut a stitched mosaic into a grid ----------
    open(inputFile);
    id = getImageID();
    W = getWidth();
    H = getHeight();
    stepX = tileW - overlap;
    stepY = tileH - overlap;
    if (stepX < 1 || stepY < 1) exit("Overlap must be smaller than the tile size.");

    config = "# Define the number of dimensions we are working on\ndim = 2\n# Define the image coordinates\n";
    keyStr = "";
    count = 0;
    row = 0;
    y = 0;
    doneY = false;
    while (!doneY) {
        col = 0;
        x = 0;
        doneX = false;
        h = minOf(tileH, H - y);
        while (!doneX) {
            w = minOf(tileW, W - x);
            cl = colLetters(col);
            rl = colLetters(row);
            if (startsWith(naming, "Row number")) label = "" + (row + 1) + cl;
            else label = rl + (col + 1);
            fileName = base + "_" + label + ext;
            selectImage(id);
            makeRectangle(x, y, w, h);
            run("Duplicate...", "duplicate title=tile_tmp");
            saveAs(fmt, outDir + fileName);
            close();
            config = config + fileName + "; ; (" + d2s(x, 1) + ", " + d2s(y, 1) + ")\n";
            keyStr = keyStr + x + "," + y + "," + w + "," + h + "," + label + "\n";
            count++;
            if (x + tileW >= W) doneX = true;
            x += stepX;
            col++;
        }
        if (y + tileH >= H) doneY = true;
        y += stepY;
        row++;
    }
    File.saveString(config, outDir + "TileConfiguration.txt");

    if (makeKey) {
        // Flatten gives an RGB copy of the original, so the original and the tiles stay untouched
        selectImage(id);
        run("Select None");
        run("Flatten");
        lw = maxOf(2, round(minOf(W, H) / 400));
        fs = maxOf(12, round(minOf(tileW, tileH) / 5));
        setLineWidth(lw);
        setColor("yellow");
        setFont("SansSerif", fs, "bold");
        lines = split(keyStr, "\n");
        for (i = 0; i < lines.length; i++) {
            p = split(lines[i], ",");
            kx = parseInt(p[0]);
            ky = parseInt(p[1]);
            drawRect(kx, ky, parseInt(p[2]), parseInt(p[3]));
            drawString(p[4], kx + lw + round(fs / 4), ky + lw + fs);
        }
        saveAs(fmt, outDir + base + "_tile_key" + ext);
        close();
    }

    selectImage(id);
    close();
    print("Grid split done: " + count + " tiles (" + row + " rows x " + col + " columns) saved to " + outDir);

} else {
    // ---------- Mode 2: save every series as its own file ----------
    run("Bio-Formats Macro Extensions");
    Ext.setId(inputFile);
    Ext.getSeriesCount(nSeries);
    saved = 0;
    for (i = 0; i < nSeries; i++) {
        Ext.setSeries(i);
        Ext.getSizeX(sx);
        Ext.getSizeY(sy);
        Ext.getSeriesName(sName);
        if (sx < minSize) {
            print("Skipping series " + (i + 1) + " (" + sx + "x" + sy + ")");
            continue;
        }
        safe = replace(sName, "[^A-Za-z0-9_\\-]", "_");
        run("Bio-Formats Importer", "open=[" + inputFile + "] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT series_" + (i + 1));
        saveAs(fmt, outDir + base + "_s" + IJ.pad(i + 1, 3) + "_" + safe + ext);
        close();
        saved++;
    }
    Ext.close();
    print("Series export done: " + saved + " of " + nSeries + " series saved to " + outDir);
}
setBatchMode(false);
