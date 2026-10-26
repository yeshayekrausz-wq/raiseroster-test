const path=require('node:path');const appDir=path.resolve(__dirname,'../desktop/display');process.chdir(appDir);
const builder=require(path.join(appDir,'node_modules/electron-builder'));
if(process.platform==='linux'){
 const util=require(path.join(appDir,'node_modules/app-builder-lib/out/targets/nsis/nsisUtil'));
 util.UninstallerReader.exec=require('./nsis-uninstaller.cjs').extract;
 require(path.join(appDir,'node_modules/app-builder-lib/out/util/macosVersion')).isMacOsCatalina=()=>true;
}
builder.build({targets:builder.Platform.WINDOWS.createTarget(['nsis'],builder.Arch.x64),publish:'never'}).catch(e=>{console.error(e);process.exitCode=1;});
