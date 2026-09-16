import { Capacitor, registerPlugin } from '@capacitor/core';
import { GateAIClientBase, GateAIError, type GateAIConfiguration } from './client';
export { GateAIError } from './client';
export type { GateAIConfiguration, GateAIContext, GateAIRequest, GateAIResponse } from './client';
const native = registerPlugin<{ execute(options: { payload: string }): Promise<{ payload: string }> }>('GateAI');
export type GateAIClient = GateAIClientBase;
export const GateAIClient = {
  async create(configuration: GateAIConfiguration): Promise<GateAIClient> {
    if (!['ios', 'android'].includes(Capacitor.getPlatform())) throw new GateAIError('unsupported_platform', 'Gate/AI requires a native iOS or Android app.');
    return GateAIClientBase.connect(async payload => (await native.execute({ payload })).payload, configuration);
  },
};
