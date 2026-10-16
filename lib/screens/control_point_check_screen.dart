import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/geo_feature.dart';
import '../models/gnss_fix.dart';
import '../services/control_point_check_service.dart';
import '../services/eov_service.dart';
import '../services/gnss/mfkrtk_provider.dart';
import '../services/gnss_info_service.dart';
import '../services/project_service.dart';

class ControlPointCheckScreen extends StatefulWidget {
  const ControlPointCheckScreen({super.key});
  @override
  State<ControlPointCheckScreen> createState() => _ControlPointCheckScreenState();
}

class _ControlPointCheckScreenState extends State<ControlPointCheckScreen> {
  static const _geometryHeightKey = '__GEOMETRY_Z__';
  String? layerId, featureId, idField, nameField, eField, nField, heightField;
  String heightReference = 'unknown';
  int duration = 30;
  bool initialized = false;
  final mapController = MapController();

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final project = context.read<ProjectService>().activeProject;
    final layer = project?.layers.where((l) => l.features.any((f) => f.type == FeatureType.point && f.geometry.isNotEmpty)).firstOrNull;
    layerId = layer?.id;
    featureId = layer?.features.where((f) => f.type == FeatureType.point && f.geometry.isNotEmpty).firstOrNull?.id;
    context.read<ControlPointCheckService>().ensureLoaded();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(l10n.controlPointCheckTitle), actions: [
      IconButton(icon: const Icon(Icons.ios_share), tooltip: 'CSV export', onPressed: () => export(context.read<ControlPointCheckService>())),
    ]),
    body: Consumer3<ProjectService, GnssInfoService, ControlPointCheckService>(
      builder: (context, projects, gnss, checks, _) {
        final project = projects.activeProject;
        final layers = project?.layers.where((l) => l.features.any((f) => f.type == FeatureType.point && f.geometry.isNotEmpty)).toList() ?? [];
        if (layerId == null || !layers.any((l) => l.id == layerId)) {
          layerId = layers.firstOrNull?.id;
          featureId = layers.firstOrNull?.features.where((f) => f.type == FeatureType.point && f.geometry.isNotEmpty).firstOrNull?.id;
          clearFields();
        }
        final layer = layers.where((l) => l.id == layerId).firstOrNull;
        final points = layer?.features.where((f) => f.type == FeatureType.point && f.geometry.isNotEmpty).toList() ?? [];
        if (!points.any((f) => f.id == featureId)) featureId = points.firstOrNull?.id;
        final selected = points.where((f) => f.id == featureId).firstOrNull;
        final eov = context.read<EovService>();
        final reference = project == null || layer == null || selected == null ? null : makeReference(project.id, layer, selected, eov);
        final provider = gnss.activeProvider;
        final mfk = provider is MfkRtkProvider ? provider : null;
        final fix = gnss.isMfkRtkActive ? gnss.lastRawFix : null;
        final sessions = reference == null ? const <ControlPointMeasurementSession>[] : checks.sessionsFor(reference.projectId, reference.featureId);
        final metrics = reference == null ? null : checks.metricsFor(reference);
        if (layers.isEmpty) return Center(child: Text(l10n.noPointLayerImportShp));
        return ListView(padding: const EdgeInsets.all(12), children: [
          selectors(layers, layer, points),
          if (layer != null && !supported(layer))
            Card(color: const Color(0xffffebee), child: Padding(padding: const EdgeInsets.all(12), child: Text(l10n.unsupportedCrsMsg))),
          if (reference != null) ...[
            mapWidget(points, selected!, reference, checks, eov),
            referenceCard(reference, layerCrsLabel(layer!)),
            liveCard(fix, gnss, eov),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              Row(children: [
                Text(l10n.measurement),
                DropdownButton<int>(value: duration, items: const [10,30,60].map((v) => DropdownMenuItem(value: v, child: Text('$v s'))).toList(),
                  onChanged: checks.isMeasuring ? null : (v) => setState(() => duration = v ?? 30)),
                const Spacer(),
                if (checks.isMeasuring) Text('${checks.remainingSeconds.ceil()} s · ${checks.epochCount} epoch'),
              ]),
              if (checks.isMeasuring) LinearProgressIndicator(value: (1-checks.remainingSeconds/checks.requestedDurationSeconds).clamp(0.0,1.0)),
              Row(children: [
                Expanded(child: FilledButton.icon(
                  onPressed: mfk != null && !checks.isMeasuring && supported(layer) ? () => start(checks, reference, mfk, eov) : null,
                  icon: const Icon(Icons.play_arrow), label: Text(l10n.startMeasurement))),
                if (checks.isMeasuring) IconButton(onPressed: checks.finishMeasurement, icon: const Icon(Icons.stop)),
              ]),
              if (mfk == null) Text(l10n.connectToMfkRtk, style: const TextStyle(color: Colors.deepOrange)),
              if (fix?.rtkStatus != RtkStatus.fixed) Text(l10n.nonFixedWarning, style: const TextStyle(color: Colors.deepOrange)),
            ]))),
            if (metrics != null && metrics.count > 0) metricsCard(metrics, reference),
            sessionsCard(sessions),
            resultsTable(points, project!.id, layer, eov, checks),
          ],
        ]);
      },
    ),
  );

  Widget selectors(List<ProjectLayer> layers, ProjectLayer? layer, List<GeoFeature> points) {
    final fields = layer?.fields ?? const [];
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      Text(l10n.refLayerAndPoint, style: const TextStyle(fontWeight: FontWeight.bold)),
      DropdownButtonFormField<String>(key: ValueKey('l-${layerId ?? ''}'), initialValue: layerId,
        decoration: InputDecoration(labelText: l10n.pointLayer),
        items: layers.map((l) => DropdownMenuItem(
          value: l.id,
          child: Text('${l.name} · ${layerCrsLabel(l)}', overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (v) => setState(() { layerId=v; featureId=null; clearFields(); })),
      DropdownButtonFormField<String>(key: ValueKey('p-${featureId ?? ''}'), initialValue: featureId,
        decoration: InputDecoration(labelText: l10n.controlPoint),
        items: points.map((f) => DropdownMenuItem(value:f.id, child:Text(pointLabel(f)))).toList(),
        onChanged: (v) => setState(() => featureId=v)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(l10n.eovFromAttributes),
        subtitle: Text(l10n.eovFromAttributesSub),
        value: eField != null && nField != null,
        onChanged: (v) => setState(() { eField=v ? fields.firstOrNull?.key : null; nField=v ? fields.skip(1).firstOrNull?.key : null; })),
      if (eField != null || nField != null) ...[
        fieldDropdown('Easting / E',eField,fields,(v)=>setState(()=>eField=v)),
        fieldDropdown('Northing / N',nField,fields,(v)=>setState(()=>nField=v)),
      ],
      fieldDropdown(l10n.pointIdField,idField,fields,(v)=>setState(()=>idField=v),none:true),
      fieldDropdown(l10n.pointNameField,nameField,fields,(v)=>setState(()=>nameField=v),none:true),
      heightDropdown(fields),
      if (heightField != null) DropdownButtonFormField<String>(initialValue:heightReference,decoration:InputDecoration(labelText:l10n.refHeightSystem),
        items:[DropdownMenuItem(value:'unknown',child:Text(l10n.unknownNoDh)),DropdownMenuItem(value:'ellipsoidal',child:Text(l10n.ellipsoidal)),DropdownMenuItem(value:'orthometric',child:Text(l10n.orthometricBaltic))],
        onChanged:(v)=>setState(()=>heightReference=v??'unknown')),
      if (layer != null) Text('Source CRS: ${layerCrsLabel(layer)}'),
    ])));
  }

  Widget heightDropdown(List<dynamic> fields) => DropdownButtonFormField<String?>(
    key: ValueKey('height-${layerId ?? ''}'), initialValue: heightField,
    decoration: InputDecoration(labelText: l10n.heightSource),
    items: [
      DropdownMenuItem<String?>(value: null, child: Text(l10n.optNo)),
      const DropdownMenuItem<String?>(value: _geometryHeightKey, child: Text('SHP geometry Z coordinate')),
      ...fields.map((f) => DropdownMenuItem<String?>(value: f.key as String, child: Text(f.label as String))),
    ],
    onChanged: (v) => setState(() => heightField = v),
  );

  Widget fieldDropdown(String label,String? value,List<dynamic> fields,ValueChanged<String?> changed,{bool none=false}) =>
    DropdownButtonFormField<String?>(key:ValueKey('$label-${layerId ?? ''}'),initialValue:fields.any((f)=>f.key==value)?value:null,
      decoration:InputDecoration(labelText:label),
      items:[if(none) DropdownMenuItem<String?>(value:null,child:Text(l10n.optNo)), ...fields.map((f)=>DropdownMenuItem<String?>(value:f.key as String,child:Text(f.label as String)))],
      onChanged:changed);

  Widget mapWidget(List<GeoFeature> points,GeoFeature selected,ControlPointReference r,ControlPointCheckService checks,EovService eov) {
    final m=checks.metricsFor(r); LatLng? average;
    if(m.meanE!=null && m.meanN!=null){final w=eov.eovToWgs(m.meanE!,m.meanN!);average=LatLng(w[0],w[1]);}
    final referenceWgs=eov.eovToWgs(r.referenceE,r.referenceN);final referencePosition=LatLng(referenceWgs[0],referenceWgs[1]);
    return SizedBox(height:220,child:ClipRRect(borderRadius:BorderRadius.circular(12),child:FlutterMap(
      mapController:mapController,
      options:MapOptions(initialCenter:selected.geometry.first,initialZoom:17,interactionOptions:const InteractionOptions(flags:InteractiveFlag.all & ~InteractiveFlag.rotate)),
      children:[
        TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.mfk.geomeasure'),
        if(average!=null) PolylineLayer(polylines:[Polyline(points:[referencePosition,average],color:Colors.deepOrange,strokeWidth:3)]),
        MarkerLayer(markers:[
          ...points.map((f)=>Marker(point:f.geometry.first,width:40,height:40,child:GestureDetector(onTap:()=>setState(()=>featureId=f.id),child:Icon(Icons.location_pin,color:f.id==selected.id?Colors.blue:Colors.red,size:36)))),
          Marker(point:referencePosition,width:36,height:36,child:const Icon(Icons.control_point,color:Colors.blue,size:32)),
          if(average!=null) Marker(point:average,width:36,height:36,child:const Icon(Icons.my_location,color:Colors.deepOrange)),
        ]),
      ],
    )));
  }

  Widget referenceCard(ControlPointReference r,String? crs)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('${l10n.controlPoint} · ${r.pointId}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),Text(r.pointName),
    Text('Ref E = ${r.referenceE.toStringAsFixed(3)} m'),Text('Ref N = ${r.referenceN.toStringAsFixed(3)} m'),
    if(r.referenceHeight!=null)Text('Ref H = ${r.referenceHeight!.toStringAsFixed(3)} m · ${r.heightReference}'),
    Text('Source: ${r.sourceLabel} · CRS: ${crs??'unknown'}'),
  ])));

  Widget liveCard(GnssFix? fix,GnssInfoService gnss,EovService eov) {
    if(fix==null)return Card(child:Padding(padding:const EdgeInsets.all(12),child:Text(l10n.waitingForMfkRtk)));
    final en=eov.wgsToEov(fix.latitude,fix.longitude);final nav=gnss.mfkRtkNavData;
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(l10n.currentMfkRtkPosition,style:const TextStyle(fontWeight:FontWeight.bold)),
      Text('E ${en[0].toStringAsFixed(3)} m · N ${en[1].toStringAsFixed(3)} m · ellipsoidal h ${fix.ellipsoidalHeight?.toStringAsFixed(3)} m'),
      Text('RTK ${fix.rtkStatus.name.toUpperCase()} · M21 ${nav?.posType??fix.positionSource??'—'} · INS ${fix.insStatus??'—'} · sats ${fix.satellitesUsed}'),
      Text('M21 reported accuracy ±${fix.horizontalAccuracy.toStringAsFixed(3)} m · heading ${fix.heading?.toStringAsFixed(1)??'—'} · roll ${fix.roll?.toStringAsFixed(1)??'—'} · pitch ${fix.pitch?.toStringAsFixed(1)??'—'}'),
    ])));
  }

  Widget metricsCard(ControlPointMetrics m,ControlPointReference r)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(l10n.aggregatedResults,style:const TextStyle(fontWeight:FontWeight.bold)),
    Text('N=${m.count} · RTK ${m.rtkStatus} · INS ${m.insStatus} · FIXED + INS ready: ${m.allFixed?l10n.optYes:l10n.optNo}'),
    metric('Mean dE',m.meanDeltaE),metric('Mean dN',m.meanDeltaN),metric('RMSE E / N',null,extra:'${fmt(m.rmseE)} / ${fmt(m.rmseN)} m'),
    metric('Mean 2D',m.meanError2d),metric('Median 2D',m.medianError2d),metric('RMSE 2D',m.rmse2d),
    metric('95th percentile',m.percentile95Error2d),metric('Maximum',m.maxError2d),
    if(r.referenceHeight!=null && r.heightReference=='unknown') const Text('ΔH not computed: reference height system unknown.'),
  ])));

  Widget metric(String label,double? v,{String? extra})=>Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(label),Text(extra??'${fmt(v)} m',style:const TextStyle(fontWeight:FontWeight.bold))]));

  Widget sessionsCard(List<ControlPointMeasurementSession> sessions) {
    if(sessions.isEmpty)return const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('No sessions for this point yet.')));
    return Card(child:ExpansionTile(title:Text(l10n.sessionsCount(sessions.length)),children:sessions.reversed.map((s){
      final m=s.metrics;final warning=s.epochs.length<s.requestedDurationSeconds||!m.allFixed;
      return ListTile(leading:Icon(warning?Icons.warning:Icons.check_circle,color:warning?Colors.orange:Colors.green),
        title:Text('${s.startedAt.toLocal()} · ${m.count} epoch · ${m.rtkStatus} / ${m.insStatus}'),
        subtitle:Text('dE ${fmt(m.meanDeltaE)} m · dN ${fmt(m.meanDeltaN)} m · RMSE 2D ${fmt(m.rmse2d)} m · 95% ${fmt(m.percentile95Error2d)} m · max ${fmt(m.maxError2d)} m'
          '${warning?'\nWarning: short or non FIXED/INS measurement.':''}'
          '${s.reference.referenceHeight==null?'':s.deltaHeight==null?'\nΔH cannot be computed: missing/different height system.':'\nΔH ${fmt(s.deltaHeight)} m'}'),
        isThreeLine:true);
    }).toList()));
  }

  Widget resultsTable(List<GeoFeature> points,String projectId,ProjectLayer layer,EovService eov,ControlPointCheckService checks) {
    final rows=<DataRow>[];
    for(final f in points){final r=makeReference(projectId,layer,f,eov);if(r==null)continue;final m=checks.metricsFor(r);
      rows.add(DataRow(selected:f.id==featureId,onSelectChanged:(_)=>setState(()=>featureId=f.id),cells:[
        DataCell(Text(r.pointId)),DataCell(Text(m.rtkStatus)),DataCell(Text(m.insStatus)),DataCell(Text(m.count.toString())),
        DataCell(Text(fmt(m.meanDeltaE))),DataCell(Text(fmt(m.meanDeltaN))),DataCell(Text(fmt(m.meanError2d))),DataCell(Text(fmt(m.rmse2d))),DataCell(Text(fmt(m.maxError2d))),
      ]));
    }
    return Card(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Padding(padding:const EdgeInsets.all(12),child:Text(l10n.controlPointSummary,style:const TextStyle(fontWeight:FontWeight.bold))),
      SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:const[
        DataColumn(label:Text('Point')),DataColumn(label:Text('RTK')),DataColumn(label:Text('INS')),DataColumn(label:Text('N')),
        DataColumn(label:Text('dE')),DataColumn(label:Text('dN')),DataColumn(label:Text('2D')),DataColumn(label:Text('RMSE 2D')),DataColumn(label:Text('Max')),
      ],rows:rows)),
    ]));
  }

  ControlPointReference? makeReference(String projectId,ProjectLayer layer,GeoFeature f,EovService eov) {
    if(!supported(layer)||f.geometry.isEmpty)return null;
    final point=f.geometry.first;final en=eov.wgsToEov(point.latitude,point.longitude);var east=en[0],north=en[1];var source='geometry layer → EOV';
    if(eField!=null&&nField!=null){final e=number(f.customData[eField]),n=number(f.customData[nField]);if(e==null||n==null)return null;east=e;north=n;source='attribute EOV fields: $eField / $nField';}
    final id=idField==null?null:f.customData[idField]?.toString().trim();final name=nameField==null?null:f.customData[nameField]?.toString().trim();
    final h=heightField==null?null:heightField==_geometryHeightKey?f.altitudes.firstOrNull:number(f.customData[heightField]);
    return ControlPointReference(projectId:projectId,layerId:layer.id,layerName:layer.name,featureId:f.id,
      pointId:id?.isNotEmpty==true?id!:f.name,pointName:name?.isNotEmpty==true?name!:f.name,referenceE:east,referenceN:north,
      referenceHeight:h,heightReference:h==null?null:heightReference,latitude:point.latitude,longitude:point.longitude,sourceLabel:source);
  }

  Future<void> start(ControlPointCheckService checks,ControlPointReference ref,MfkRtkProvider provider,EovService eov) async {
    try{await checks.startMeasurement(reference:ref,provider:provider,eovService:eov,durationSeconds:duration);}
    catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Measurement start error: $error')));}
  }

  Future<void> export(ControlPointCheckService checks) async {
    await checks.ensureLoaded();final sessions=checks.allSessions;
    if(sessions.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(l10n.noExportableMeasurements)));return;}
    String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    const headers='point_id,point_name,ref_e,ref_n,ref_h,ref_h_type,measured_e,measured_n,measured_h_ellipsoidal,delta_e,delta_n,delta_h,error_2d,mean_error_2d,median_error_2d,rmse_e,rmse_n,rmse_2d,p95_error_2d,max_error_2d,epoch_count,rtk_status,ins_status,satellites,start_time,end_time,reference_source,m21_reported_accuracy_mean';
    final csv=StringBuffer()..writeln(headers);
    for(final s in sessions){final m=s.metrics;final last=s.epochs.isEmpty?null:s.epochs.last;
      final values=[s.reference.pointId,s.reference.pointName,s.reference.referenceE,s.reference.referenceN,s.reference.referenceHeight,s.reference.heightReference,m.meanE,m.meanN,m.meanHeight,m.meanDeltaE,m.meanDeltaN,s.deltaHeight,m.meanError2d,m.meanError2d,m.medianError2d,m.rmseE,m.rmseN,m.rmse2d,m.percentile95Error2d,m.maxError2d,m.count,m.rtkStatus,m.insStatus,last?.satellites,s.startedAt.toIso8601String(),s.endedAt.toIso8601String(),s.reference.sourceLabel,m.meanHorizontalAccuracy];
      csv.writeln(values.map(q).join(','));
    }
    try{final dir=await getTemporaryDirectory();final file=File('${dir.path}/control_point_check.csv');await file.writeAsString(csv.toString());await SharePlus.instance.share(ShareParams(files:[XFile(file.path)],text:l10n.controlPointCheckTitle));}
    catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(l10n.csvExportError(error.toString()))));}
  }

  String pointLabel(GeoFeature f){final id=idField==null?null:f.customData[idField]?.toString().trim();return id?.isNotEmpty==true?'${id!} · ${f.name}':f.name;}
  bool supported(ProjectLayer layer) {
    final v = (layer.crsInfo ?? '').toUpperCase();
    return v.contains('23700') ||
        v.contains('EOV') ||
        v.contains('HD72') ||
        v.contains('4326') ||
        v.contains('WGS84') ||
        v.contains('CRS84') ||
        layer.coordinateCrs == LayerCrs.eov ||
        layer.coordinateCrs == LayerCrs.wgs84;
  }

  String layerCrsLabel(ProjectLayer layer) =>
      layer.crsInfo ?? layer.coordinateCrs.label;
  double? number(dynamic v)=>v is num?v.toDouble():double.tryParse(v?.toString().trim().replaceAll(',','.')??'');
  String fmt(double? v)=>v==null?'—':v.toStringAsFixed(3);
  void clearFields(){idField=null;nameField=null;eField=null;nField=null;heightField=null;heightReference='unknown';}
  @override
  void dispose(){mapController.dispose();super.dispose();}
}
