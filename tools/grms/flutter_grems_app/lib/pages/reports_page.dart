import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../providers/reports_provider.dart';
import '../utils/web_download_helper.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  final Map<ReportType, DateTime?> _startDates = {};
  final Map<ReportType, DateTime?> _endDates = {};

  @override
  void initState() {
    super.initState();
    for (var type in ReportType.values) {
      _startDates[type] = DateTime.now().subtract(const Duration(days: 7));
      _endDates[type] = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportsService = ref.watch(reportsServiceProvider);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReportRow(
              context,
              reportsService,
              ReportType.alarm,
              'Alarm Reports',
              'Historical alarm data and response times',
              Icons.notifications_active_outlined,
            ),
            const SizedBox(height: 16),
            _buildReportRow(
              context,
              reportsService,
              ReportType.service,
              'Service Reports',
              'Room service status and workflow statistics',
              Icons.room_service_outlined,
            ),
            const SizedBox(height: 16),
            _buildReportRow(
              context,
              reportsService,
              ReportType.energy,
              'Energy Reports',
              'Analysis of energy usage across all rooms',
              Icons.bar_chart_rounded,
            ),
            const SizedBox(height: 16),
            _buildReportRow(
              context,
              reportsService,
              ReportType.activity,
              'Activity Reports',
              'Combined alarm and room service history',
              Icons.receipt_long_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportRow(
    BuildContext context,
    ReportsService service,
    ReportType type,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Card(
      elevation: 0,
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.blue.shade200, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _DateButton(
                    label: _startDates[type] == null
                        ? 'Start Date'
                        : DateFormat(
                            'yyyy-MM-dd',
                          ).format(_startDates[type]!),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDates[type] ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _startDates[type] = picked);
                      }
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('-', style: TextStyle(color: Colors.grey)),
                  ),
                  _DateButton(
                    label: _endDates[type] == null
                        ? 'End Date'
                        : DateFormat('yyyy-MM-dd').format(_endDates[type]!),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDates[type] ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _endDates[type] = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            _buildActionButtons(context, service, type),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ReportsService service,
    ReportType type,
  ) {
    return Row(
      children: [
        _SmallActionBtn(
          label: 'CSV',
          color: Colors.green,
          onTap: () => _handleExport(service, type, 'csv'),
        ),
        const SizedBox(width: 8),
        _SmallActionBtn(
          label: 'PDF',
          color: Colors.red,
          onTap: () => _handleExport(service, type, 'pdf'),
        ),
        const SizedBox(width: 8),
        _SmallActionBtn(
          label: 'XLS',
          color: Colors.blue,
          onTap: () => _handleExport(service, type, 'xls'),
        ),
        const SizedBox(width: 16),
        TextButton(
          onPressed: () => _showPreview(context, service, type),
          child: const Text('Preview', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<void> _handleExport(
    ReportsService service,
    ReportType type,
    String format,
  ) async {
    final report = service.buildReport(type, _startDates[type], _endDates[type]);
    if (report == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select valid dates')),
      );
      return;
    }

    if (format == 'csv' || format == 'xls') {
      final csv = service.convertToCSV(report);
      final filename = format == 'csv'
          ? '${report.filename}.csv'
          : '${report.filename}.xls';
      WebDownloadHelper.downloadFile(filename, utf8.encode(csv));
    } else if (format == 'pdf') {
      final pdfBytes = await _buildReportPdf(report);
      WebDownloadHelper.downloadFile('${report.filename}.pdf', pdfBytes);
    }
  }

  void _showPreview(
    BuildContext context,
    ReportsService service,
    ReportType type,
  ) {
    final report = service.buildReport(type, _startDates[type], _endDates[type]);
    if (report == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select valid dates')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Report Preview',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          report.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: report.rows.isEmpty
                    ? const Center(
                        child: Text(
                          'No records found for the selected range.',
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Table(
                          border: TableBorder.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.3),
                              ),
                              children: report.headers
                                  .map(
                                    (h) => Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        h,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            ...report.rows.map(
                              (row) => TableRow(
                                children: row
                                    .map(
                                      (cell) => Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          cell.toString(),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _buildReportPdf(ReportData report) async {
    final pdf = pw.Document();
    final generatedAt = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Text(
            report.title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Generated at: $generatedAt'),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: report.headers,
            data: report.rows
                .map((row) => row.map((e) => e.toString()).toList())
                .toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(6),
            border: pw.TableBorder.all(
              color: PdfColors.grey400,
              width: 0.5,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    return pdf.save();
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _SmallActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
