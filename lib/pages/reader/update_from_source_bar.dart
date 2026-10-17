import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../shared/cooldown.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/kit/kit.dart';
import 'supersession_confirm.dart';

/// `screens/reader.md` §Source freshness — **Update from {Provider}, any time**
/// (5.12.0, ADR-172). The banner offers the update only when the provider copy
/// is newer; this is the reader pulling the current version NOW, whatever
/// freshness says and without waiting out a sync's 30-minute quiet period.
/// Same endpoint, same confirm and the same wait key as the banner, so the two
/// controls hold together. Write before you move: nothing changes until the
/// call has succeeded. Web: `src/pages/reader/UpdateFromSourceBar.jsx`.
class UpdateFromSourceBar extends StatefulWidget {
  final String docId;
  final Document doc;
  const UpdateFromSourceBar({super.key, required this.docId, required this.doc});

  @override
  State<UpdateFromSourceBar> createState() => _UpdateFromSourceBarState();
}

class _UpdateFromSourceBarState extends State<UpdateFromSourceBar> {
  bool _updating = false;
  bool _queued = false;
  String? _error;

  String? get _provider => widget.doc.sourceIntegration?['provider'] as String?;

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    final res = await SupersessionConfirm.run(
      context,
      docId: widget.docId,
      title: SupersessionConfirm.updateTitle,
      lead: SupersessionConfirm.updateLead(_provider),
      confirmLabel: SupersessionConfirm.updateConfirmLabel,
      study: SupersessionConfirm.updateStudy,
      editedBy: SupersessionConfirm.updateEditedBy(_provider),
      action: () async {
        try {
          await Api.instance.updateFromSource(widget.docId);
          return null;
        } on ApiException catch (e) {
          return e.message;
        } catch (_) {
          return 'Update failed.';
        }
      },
      waitKey: WaitKey.sourceRefresh(widget.docId),
    );
    if (!mounted) return;
    setState(() {
      _updating = false;
      switch (res.outcome) {
        case SupersessionOutcome.done:
          _queued = true;
        case SupersessionOutcome.refused:
          // A cooldown with its number is the control's wait and says itself
          // until it ends (4.107.0, ADR-140).
          _error = res.waits ? null : res.message;
        case SupersessionOutcome.kept:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null || widget.doc.status != DocumentStatus.complete) {
      return const SizedBox.shrink();
    }
    final name = SupersessionConfirm.providerName(provider);
    return KitWait(
      waitKey: WaitKey.sourceRefresh(widget.docId),
      builder: (context, wait) {
        final slot = kitRefusalSlot(wait, _error);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_queued)
                Text(
                  'Update queued — this source is being re-imported from $name. Its content will refresh when processing finishes.',
                  style: KitText.meta(context),
                )
              else
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text('Imported from $name', style: KitText.meta(context)),
                    KitButton.secondary(
                      _updating ? 'Queuing…' : 'Update from $name',
                      wait: _updating ? 0 : wait.left,
                      onPressed: _updating ? null : _update,
                    ),
                  ],
                ),
              if (slot != null) ...[
                const SizedBox(height: 6),
                slot,
              ],
            ],
          ),
        );
      },
    );
  }
}
